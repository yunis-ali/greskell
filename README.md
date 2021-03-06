# greskell - Haskell binding for Gremlin graph query language

greskell is a toolset to build and execute [Gremlin graph query language](http://tinkerpop.apache.org/gremlin.html) in Haskell.

Contents:

- [The Greskell type](#the-greskell-type)
- [Build variable binding](#build-variable-binding)
- [Submit to the Gremlin Server](#submit-to-the-gremlin-server)
- [DSL for graph traversals](#dsl-for-graph-traversals)
- [Type parameters of GTraversal and Walk](#type-parameters-of-gtraversal-and-walk)
- [Restrict effect of GTraversal by WalkType](#restrict-effect-of-gtraversal-by-walktype)
- [Submit GTraversal](#submit-gtraversal)
- [Graph structure types](#graph-structure-types)
- [GraphSON parser](#graphson-parser)
- [Make your own graph structure types](#make-your-own-graph-structure-types)


## Prelude

Because this README is also a test script, first we import common modules.

```haskell common
{-# LANGUAGE OverloadedStrings, QuasiQuotes, TypeFamilies #-}
import Control.Category ((>>>))
import Control.Monad (guard)
import Data.Monoid (mempty)
import Data.Text (Text)
import qualified Data.HashMap.Strict as HM
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.Function ((&))
import Text.Heredoc (here)
import Test.Hspec
```

## The Greskell type

At the core of greskell is the `Greskell` type. `Greskell a` represents a Gremlin expression that evaluates to the type `a`.

```haskell Greskell
import Data.Greskell.Greskell (Greskell, toGremlin)

literalText :: Greskell Text
literalText = "foo"

literalInt :: Greskell Int
literalInt = 200
```

You can convert `Greskell` into Gremlin `Text` script by `toGremlin` function.

```haskell Greskell
main = hspec $ specify "Greskell" $ do
  toGremlin literalText `shouldBe` "\"foo\""
```

`Greskell` implements instances of `IsString`, `Num`, `Fractional` etc. so you can use methods of these classes to build `Greskell`.

```haskell Greskell
  toGremlin (literalInt + 30 * 20) `shouldBe` "(200)+((30)*(20))"
```

## Build variable binding

Gremlin Server supports [parameterized scripts](http://tinkerpop.apache.org/docs/current/reference/#parameterized-scripts), where a client can send a Gremlin script and variable binding.

greskell's `Binder` monad is a simple monad that manages bound variables and their values. With `Binder`, you can inject Haskell values into Greskell.

```haskell Binder
import Data.Greskell.Greskell (Greskell, toGremlin)
import Data.Greskell.Binder (Binder, newBind, runBinder)

plusTen :: Int -> Binder (Greskell Int)
plusTen x = do
  var_x <- newBind x
  return $ var_x + 10
```

`newBind` creates a new Gremlin variable unique in the `Binder`'s monadic context, and returns that variable.

```haskell Binder
main = hspec $ specify "Binder" $ do
  let (script, binding) = runBinder $ plusTen 50
  toGremlin script `shouldBe` "(__v0)+(10)"
  binding `shouldBe` HM.fromList [("__v0", A.Number 50)]
```

`runBinder` function returns the `Binder`'s monadic result and the created binding.


## Submit to the Gremlin Server

To connect to the Gremlin Server and submit your Gremlin script, use [greskell-websocket](http://hackage.haskell.org/package/greskell-websocket) package.

```haskell submit
import Control.Exception.Safe (bracket, try, SomeException)
import Data.Foldable (toList)
import Data.Greskell.Greskell (Greskell) -- from greskell package
import Data.Greskell.Binder -- from greskell package
  (Binder, newBind, runBinder)
import Network.Greskell.WebSocket -- from greskell-websocket package
  (connect, close, submit, slurpResults)

submitExample :: IO [Int]
submitExample =
  bracket (connect "localhost" 8182) close $ \client -> do
    let (g, binding) = runBinder $ plusTen 50
    result_handle <- submit client g (Just binding)
    fmap toList $ slurpResults result_handle

plusTen :: Int -> Binder (Greskell Int)
plusTen x = do
  var_x <- newBind x
  return $ var_x + 10

main = hspec $ specify "submit" $ do
  egot <- try submitExample :: IO (Either SomeException [Int])
  case egot of
    Left _ -> return () -- probably there's no server running
    Right got -> got `shouldBe` [60]
```

`submit` function sends a `Greskell` to the server and returns a `ResultHandle`. `ResultHandle` is a stream of evaluation results returned by the server. `slurpResults` gets all items from `ResultHandle`.


## DSL for graph traversals

greskell has a domain-specific language (DSL) for building Gremlin [Traversal](http://tinkerpop.apache.org/docs/current/reference/#traversal) object. Two data types, `GTraversal` and `Walk`, are especially important in this DSL.

`GTraversal` is simple. It's just the greskell counterpart of [GraphTraversal](http://tinkerpop.apache.org/javadocs/current/full/org/apache/tinkerpop/gremlin/process/traversal/dsl/graph/GraphTraversal.html) class in Gremlin.

`Walk` is a little tricky. It represents a chain of one or more method calls on a GraphTraversal object. In Gremlin, those methods are called "[graph traversal steps](http://tinkerpop.apache.org/docs/current/reference/#graph-traversal-steps)." greskell defines those traversal steps as functions returning a `Walk` object.

For example,

```haskell GTraversal
import Data.Greskell.Greskell (toGremlin, Greskell)
import Data.Greskell.GTraversal
  ( GTraversal, Transform, Walk, source, sV,
    gHasLabel, gHas2, (&.), ($.)
  )
import Data.Greskell.Graph (AVertex)

allV :: GTraversal Transform () AVertex
allV = source "g" & sV []

isPerson :: Walk Transform AVertex AVertex
isPerson = gHasLabel "person"

isMarko :: Walk Transform AVertex AVertex
isMarko = gHas2 "name" "marko"

main = hspec $ specify "GTraversal" $ do
  toGremlin (allV &. isPerson &. isMarko)
    `shouldBe`
    "g.V().hasLabel(\"person\").has(\"name\",\"marko\")"
```

In the above example, `allV` is the GraphTraversal obtained by `g.V()`. `isPerson` and `isMarko` are method calls of `.hasLabel` and `.has` steps, respectively. `(&.)` operator combines a `GTraversal` and `Walk` to get an expression that the graph traversal steps are executed on the GraphTraversal.

The above example also uses `AVertex` type. `AVertex` is a type for a graph vertex. We will explain it in detail later in [Graph structure types](#graph-structure-types).

Note that we use `(&)` operator in the definition of `allV`. `(&)` operator from [Data.Function](http://hackage.haskell.org/package/base/docs/Data-Function.html) module is just the flip of `($)` operator. Likewise, greskell defines `($.)` operator, so we could also write the above expression as follows.

```haskell GTraversal
  (toGremlin $ isMarko $. isPerson $. sV [] $ source "g")
    `shouldBe`
    "g.V().hasLabel(\"person\").has(\"name\",\"marko\")"
```

## Type parameters of GTraversal and Walk

`GTraversal` and `Walk` both have the same type parameters.

```haskell
GTraversal walk_type start end
Walk       walk_type start end
```

`GTraversal` and `Walk` both take the traversers with data of type `start`, and emit the traversers with data of type `end`. We will explain `walk_type` [later](#restrict-effect-of-gtraversal-by-walktype).

`Walk` is very similar to function `(->)`. That is why it is an instance of `Category`, so you can compose `Walk`s together. The example in the last section can also be written as

```haskell GTraversal
  let composite_walk = isPerson >>> isMarko
  toGremlin (source "g" & sV [] &. composite_walk)
    `shouldBe`
    "g.V().hasLabel(\"person\").has(\"name\",\"marko\")"
```

## Restrict effect of GTraversal by WalkType

The first type parameter of `GTraversal` and `Walk` is called "walk type". Walk type is a type marker to describe effect of the graph traversal. There are three walk types, `Filter`, `Transform` and `SideEffect`. All of them are instance of `WalkType` class.

- Walks of `Filter` type do filtering only. It takes input traversers and emits some of them. It does nothing else. Example: `.has` and `.filter` steps.
- Walks of `Transform` type may transform the input traversers but have no side effects. Example: `.map` and `.out` steps.
- Walks of `SideEffect` type may alter the "side effect" context of the Traversal object or the state outside the Traversal object. Example: `.aggregate` and `.addV` steps.

Walk types are hierarchical. `Transform` is more powerful than `Filter`, and `SideEffect` is more powerful than `Transform`. You can "lift" a walk with a certain walk type to one with a more powerful walk type by `liftWalk` function.

```haskell WalkType
import Data.Greskell.GTraversal
  ( Walk, Filter, Transform, SideEffect, GTraversal,
    liftWalk, source, sV, (&.),
    gHasLabel, gHas1, gAddV, gValues, gIdentity
  )
import Data.Greskell.Graph (AVertex)
import Data.Greskell.Greskell (toGremlin)
import Network.Greskell.WebSocket (Client, ResultHandle, submit)

hasAge :: Walk Filter AVertex AVertex
hasAge = gHas1 "age"

hasAge' :: Walk Transform AVertex AVertex
hasAge' = liftWalk hasAge
```

Now what are these walk types useful for? Well, it allows you to build graph traversals in a safer way than you do with plain Gremlin.

In Haskell, we can distinguish pure and non-pure functions using, for example, `IO` monad. Likewise, we can limit power of traversals by using `Filter` or `Transform` walk types explicitly. That way, we can avoid executing unwanted side-effect accidentally.

```haskell WalkType
nameOfPeople :: Walk Filter AVertex AVertex -> GTraversal Transform () Text
nameOfPeople pfilter =
  source "g" & sV [] &. gHasLabel "person" &. liftWalk pfilter &. gValues ["name"]

newPerson :: Walk SideEffect s AVertex
newPerson = gAddV "person"

main = hspec $ specify "liftWalk" $ do
  ---- This compiles
  toGremlin (nameOfPeople hasAge)
    `shouldBe` "g.V().hasLabel(\"person\").has(\"age\").values(\"name\")"

  ---- This doesn't compile.
  ---- It's impossible to pass a SideEffect walk to an argument that expects Filter.
  -- toGremlin (nameOfPeople newPerson)
  --   `shouldBe` "g.V().hasLabel(\"person\").addV(\"person\").values(\"name\")"
```

In the above example, `nameOfPeople` function takes a `Filter` walk and creates a `Transform` walk. There is no way to pass a `SideEffect` walk (like `gAddV`) to `nameOfPeople` because `Filter` is weaker than `SideEffect`. That way, we can be sure that the result traversal of `nameOfPeople` function never has any side-effect (thus its walk type is just `Transform`.)


## Submit GTraversal

You can submit `GTraversal` directly to the Gremlin Server. Submitting `GTraversal c s e` yeilds `ResultHandle e`, so you can get the traversal results in a stream.

```haskell WalkType
getNameOfPeople :: Client -> IO (ResultHandle Text)
getNameOfPeople client = submit client (nameOfPeople gIdentity) Nothing
```


## Graph structure types

Graph structure interfaces in Gremlin are represented as type-classes in greskell. We have `Element`, `Vertex`, `Edge` and `Property` type-classes for the interfaces of the same name.

The reason why we use type-classes is that it allows you to define your own data types as a graph structure. See ["Make your own graph structure types"](#make-your-own-graph-structure-types) below in detail.

Nonetheless, it is convenient to have some generic data types we can use for graph structure types. For that purpose, we have `AVertex`, `AEdge`, `AVertexProperty` and `AProperty` types.

Those types are useful because some functions are too polymorphic for the compiler to infer the types for its "start" and "end".

```haskell monomorphic
import Data.Greskell.Greskell (toGremlin)
import Data.Greskell.Graph (AVertex)
import Data.Greskell.GTraversal
  ( GTraversal, Transform,
    source, (&.), sV, gOut, sV', gOut',
  )

main = hspec $ specify "monomorphic walk" $ do
  ---- This doesn't compile
  -- toGremlin (source "g" & sV [] &. gOut []) `shouldBe` "g.V().out()"

  -- This compiles, with type annotation.
  let gv :: GTraversal Transform () AVertex
      gv = source "g" & sV []
      gvo :: GTraversal Transform () AVertex
      gvo = gv &. gOut []
  toGremlin gvo `shouldBe` "g.V().out()"
  
  -- This compiles, with monomorphic functions.
  toGremlin (source "g" & sV' [] &. gOut' []) `shouldBe` "g.V().out()"
```

In the above example, `sV` and `gOut` are polymorphic with `Vertex` constraint, so the compiler would complain about the ambiguity. In that case, you can add explicit type annotations of `AVertex` type, or use monomorphic versions, `sV'` and `gOut'`.


## GraphSON parser

`A` in `AVertex` stands for "Aeson". That means this type is based on the data type from [Data.Aeson](http://hackage.haskell.org/package/aeson/docs/Data-Aeson.html) module. With Aeson, greskell implements parsers for GraphSON.

[GraphSON](http://tinkerpop.apache.org/docs/current/dev/io/#graphson) is a format to encode graph structure types into JSON. As of this writing, there are three slightly different versions of GraphSON. This makes the graph structure types a little complicated.

To support GraphSON decoding, we introduced the following symbols:

- `GraphSON` type: `GraphSON a` has data of type `a` and optional "type string" that describes the type of that data.
- `GValue` type: basically Aeson's `Value` enhanced with `GraphSON`.
- `FromGraphSON` type-class: types that can be parsed from `GValue`. It's analogous to Aeson's `FromJSON`.

`AVertex`, `AEdge`, `AVertexProperty` and `AProperty` types implement `FromGraphSON` instance, so they can be parsed from GraphSON v1, v2 and v3 formats.

```haskell GraphSON
import Data.Greskell.GraphSON
  ( nonTypedGValue, typedGValue', GValueBody(GNumber, GString)
  )
import Data.Greskell.Graph
  ( AVertex(..), AVertexProperty(..),
    fromProperties
  )

vertex_GraphSONv1 = [here|
{
  "id" : 1,
  "label" : "person",
  "type" : "vertex",
  "properties" : {
    "name" : [ {
      "id" : 0,
      "value" : "marko"
    } ]
  }
}
|]

vertex_GraphSONv3 = [here|
{
  "@type" : "g:Vertex",
  "@value" : {
    "id" : {
      "@type" : "g:Int32",
      "@value" : 1
    },
    "label" : "person",
    "properties" : {
      "name" : [ {
        "@type" : "g:VertexProperty",
        "@value" : {
          "id" : {
            "@type" : "g:Int64",
            "@value" : 0
          },
          "value" : "marko",
          "label" : "name"
        }
      } ]
    }
  }
}
|]

decoded_vertex_GraphSONv1 =
  AVertex 
  { avId = nonTypedGValue $ GNumber 1,
    avLabel = "person",
    avProperties = fromProperties [
      AVertexProperty
      { avpId = nonTypedGValue $ GNumber 0,
        avpLabel = "name",
        avpValue = nonTypedGValue $ GString "marko",
        avpProperties = mempty
      }
    ]
  }

decoded_vertex_GraphSONv3 =
  AVertex 
  { avId = typedGValue' "g:Int32" $ GNumber 1,
    avLabel = "person",
    avProperties = fromProperties [
      AVertexProperty
      { avpId = typedGValue' "g:Int64" $ GNumber 0,
        avpLabel = "name",
        avpValue = nonTypedGValue $ GString "marko",
        avpProperties = mempty
      }
    ]
  }


main = hspec $ specify "GraphSON" $ do
  A.eitherDecode vertex_GraphSONv1 `shouldBe` Right decoded_vertex_GraphSONv1
  A.eitherDecode vertex_GraphSONv3 `shouldBe` Right decoded_vertex_GraphSONv3
```

As you can see in the above example, the vertex object in GraphSON version 3 has `@type` and `@value` fields, while version 1 does not. `AVertex` can parse both versions. The `@type` field, if present, is stored in `GValue` type.


## Make your own graph structure types

When you use a graph database, I think you usually encode your application-specific data types as graph data structures, and store them in the database. greskell supports directly embedding your application-specific data types into graph data structures.

### Vertex

For example, let's make the following `Person` type a graph Vertex.

```haskell own_types
import Data.Greskell.Graph
  ( Element(..), Vertex, Edge(..), Property(..),
    AVertexProperty, AVertex(..), AProperty,
    parseOneValue
  )
import Data.Greskell.GraphSON (FromGraphSON(parseGraphSON), Parser)
import Data.Greskell.Greskell (toGremlin)
import Data.Greskell.GTraversal
  ( GTraversal, Transform,
    source, sV, gHasLabel, gHas2, (&.)
  )

data Person =
  Person
  { personId :: Int,
    personName :: Text,
    personAge :: Int
  }
```

In that case, just make it instances of `Element` and `Vertex` type-classes.

```haskell own_types
instance Element Person where
  type ElementID Person = Int
  type ElementProperty Person = AVertexProperty

instance Vertex Person
```

`Element` type-class has two associated types.

- `ElementID` is the type of the vertex ID. It depends on your graph database implementation and settings.
- `ElementProperty` is the type of the property of the vertex. If you don't care, you can use `AVertexProperty`.

Once `Person` is a `Vertex`, you can use it in greskell's traversal DSL.

```haskell own_types
main = hspec $ specify "your own graph types" $ do
  let get_marko :: GTraversal Transform () Person
      get_marko = source "g" & sV [] &. gHasLabel "person" &. gHas2 "name" "marko"
  toGremlin get_marko `shouldBe` "g.V().hasLabel(\"person\").has(\"name\",\"marko\")"
```

In addition, you can easily implement `FromGraphSON` instance for `Person` type using `AVertex`.

```haskell own_types
instance FromGraphSON Person where
  parseGraphSON v = fromAVertex =<< parseGraphSON v
    where
      fromAVertex :: AVertex -> Parser Person
      fromAVertex av = do
        guard (avLabel av == "person")
        pid <- parseGraphSON $ avId av
        name <- parseOneValue "name" $ avProperties av
        age <- parseOneValue "age" $ avProperties av
        return $ Person pid name age
```

Using `AVertex` as an intermediate type, you can now parse GraphSON (in any version!) vertex into `Person` type. With `FromGraphSON` instance, you can directly get `Person` from the Gremlin Server.

Like the above example of `Person`, you can make your own types for other graph structures.

### Edge

For an `Edge`, make it instances of `Element` and `Edge`. You can use `AProperty` for `ElementProperty` if you don't care.

```haskell own_types
data MyEdge = MyEdge

instance Element MyEdge where
  type ElementID MyEdge = Text
  type ElementProperty MyEdge = AProperty

instance Edge MyEdge where
  type EdgeVertexID MyEdge = Integer
```

### Property

For a simple `Property`, make it instance of `Property`. Note that the kind of a property type has to be `(* -> *)`.

```haskell own_types
data MyProperty v = MyProperty v

instance Property MyProperty where
  propertyKey _ = "key"
  propertyValue (MyProperty v) = v
```

### VertexProperty

For a `VertexProperty`, just make it instances of `Element` and `Property`. We don't have `VertexProperty` type-class, because `Element` and `Property` have different kinds. You can use `AProperty` for `ElementProperty` if you don't care.

```haskell own_types
data MyVertexProperty v = MyVertexProperty v

instance Element (MyVertexProperty v) where
  type ElementID (MyVertexProperty v) = Int
  type ElementProperty (MyVertexProperty v) = AProperty

instance Property MyVertexProperty where
  propertyKey _ = "key"
  propertyValue (MyVertexProperty v) = v
```


## Todo

- Complete graph traversal steps API.


## Author

Toshio Ito <debug.ito@gmail.com>
