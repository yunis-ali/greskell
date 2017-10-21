{-# LANGUAGE OverloadedStrings #-}
module Data.Greskell.GTraversalSpec (main,spec) where

import Control.Category ((>>>), (<<<))
import Data.Aeson (ToJSON(..))
import Data.Either (isRight)
import Data.Function ((&))
import Data.Text (Text)
import Language.Haskell.Interpreter
  ( loadModules, OptionVal((:=)), set, searchPath,
    setTopLevelModules, runInterpreter, InterpreterError,
    typeOf
  )
import System.IO (stderr, hPutStrLn)

import Test.Hspec

import Data.Greskell.Gremlin
  ( oIncr, oDecr, oShuffle,
    pEq, pNeq, pInside
  )
import Data.Greskell.Graph
  ( Element,
    Key,
    tLabel, tId
  )
import Data.Greskell.Greskell (toGremlin, Greskell, unsafeGreskell)
import Data.Greskell.GTraversal
  ( Walk, Transform,
    source, vertices', edges', (&.), ($.),
    gHas1, gHas2, gHasLabel, gHasId,
    gOut', gRange, gValues, gNot, gIn',
    gOrderBy, ByComparator(ByComp), ByProjection,
    pjEmpty, pjT, pjTraversal, pjKey
  )


main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  spec_WalkType_classes
  spec_GraphTraversalSource
  spec_order_by
  spec_compose_steps
  spec_has

spec_WalkType_classes :: Spec
spec_WalkType_classes = do
  describe "Split typeclass" $ do
    let c = checkSplitCompatible
    c "Filter" "Filter" True
    c "Filter" "Transform" True
    c "Filter" "SideEffect" True
    c "Transform" "Filter" True
    c "Transform" "Transform" True
    c "Transform" "SideEffect" True
    c "SideEffect" "Filter" False
    c "SideEffect" "Transform" False
    c "SideEffect" "SideEffect" True
  describe "Lift typeclass" $ do
    let c = checkLiftCompatible
    c "Filter" "Filter" True
    c "Filter" "Transform" True
    c "Filter" "SideEffect" True
    c "Transform" "Filter" False
    c "Transform" "Transform" True
    c "Transform" "SideEffect" True
    c "SideEffect" "Filter" False
    c "SideEffect" "Transform" False
    c "SideEffect" "SideEffect" True
  
toErrString :: Either InterpreterError a -> Either String a
toErrString (Right a) = Right a
toErrString (Left e) = Left $ show e

checkWalkTypeRelation :: (String -> String -> String) -> String -> String -> Bool -> Spec
checkWalkTypeRelation makeCode child parent expect_ok = specify label $ doCheck
  where
    label = child ++ " -> " ++ parent
    doCheck = do
      result <- fmap toErrString $ runInterpreter compiledParent
      -- hPutStrLn stderr ("## " ++ label ++ ": " ++ show result)
      isRight result `shouldBe` expect_ok
    compiledParent = do
      set [searchPath := ["src"]]
      loadModules ["src/Data/Greskell/GTraversal.hs"]
      setTopLevelModules ["Data.Greskell.GTraversal"]
      typeOf $ makeCode child parent

checkSplitCompatible :: String -> String -> Bool -> Spec
checkSplitCompatible = checkWalkTypeRelation makeCode
  where
    makeCode child parent =
      "let f :: Walk " ++ child ++ " s s -> Walk " ++ parent ++ " s s; "
      ++ "f = gFilter; "
      ++ "child :: Walk " ++ child ++ " s s; "
      ++ "child = undefined; "
      ++ "in f child"

checkLiftCompatible :: String -> String -> Bool -> Spec
checkLiftCompatible = checkWalkTypeRelation makeCode
  where
    makeCode child parent =
      "let f :: Walk " ++ child ++ " s e -> Walk " ++ parent ++ " s e; "
      ++ "f = liftWalk; "
      ++ "in f"

spec_GraphTraversalSource :: Spec
spec_GraphTraversalSource = describe "GraphTraversalSource" $ do
  specify "g.V()" $ do
    (toGremlin $ vertices' [] $ source "g") `shouldBe` ("g.V()")
  specify "g.V(1,2,3)" $ do
    let ids = [1,2,3] :: [Greskell Int]
    (toGremlin $ vertices' (map (fmap toJSON) ids) $ source "g") `shouldBe` ("g.V(1,2,3)")

spec_order_by :: Spec
spec_order_by = describe "gOrderBy" $ do
  let gv = source "g" & vertices' []
  specify "no arg" $ do
    toGremlin (gv &. gOrderBy []) `shouldBe` "g.V().order()"
  specify "empty projection" $ do
    toGremlin (gv &. gOrderBy [ByComp pjEmpty oIncr]) `shouldBe` "g.V().order().by(incr)"
  specify "traversal projection" $ do
    toGremlin (gv &. gOrderBy [ByComp (pjTraversal $ gOut' ["foo"] >>> gIn' ["bar"]) oShuffle])
      `shouldBe` "g.V().order().by(__.out(\"foo\").in(\"bar\"),shuffle)"
  specify "value projection" $ do
    let nameKey :: Key e Text
        nameKey = "name"
    toGremlin (gv &. gOrderBy [ByComp (pjKey nameKey) oDecr]) `shouldBe` "g.V().order().by(\"name\",decr)"
  specify "T token projection" $ do
    toGremlin (gv &. gOrderBy [ByComp (pjT tLabel) oIncr]) `shouldBe` "g.V().order().by(label,incr)"
  specify "two by steps of different comparison types" $ do
    let ageKey :: Key e Int
        ageKey = "age"
    toGremlin (gv &. gOrderBy [ByComp (pjKey ageKey) oDecr, ByComp (pjT tId) oDecr])
      `shouldBe` "g.V().order().by(\"age\",decr).by(id,decr)"
  specify "IsString instance of ByProjection" $ do
    toGremlin (gv &. gOrderBy [ByComp "name" oIncr])
      `shouldBe` "g.V().order().by(\"name\",incr)"

spec_compose_steps :: Spec
spec_compose_steps = describe "DSL to compose steps" $ do
  specify "(&) and (&.)" $ do
    let gt = source "g" & vertices' [] &. gHas2 ("x" :: Key e Int) (pEq 100) &. gOut' [] &. gRange 0 100
    toGremlin gt `shouldBe` "g.V().has(\"x\",eq(100)).out().range(0,100)"
  specify "(&) and (&.) and (>>>)" $ do
    let gt = source "g" & vertices' [unsafeGreskell "200"] &. (gOut' [] >>> gOut' ["friends_to"] >>> gValues ["name"])
    toGremlin gt `shouldBe` "g.V(200).out().out(\"friends_to\").values(\"name\")"
  specify "($) and ($.)" $ do
    let gt = gRange 20 30 $. gNot (gOut' ["friends_to"]) $. vertices' [] $ source "g"
    toGremlin gt `shouldBe` "g.V().not(__.out(\"friends_to\")).range(20,30)"
  specify "($) and ($.) and (<<<)" $ do
    let gt = gHas2 ("name" :: Key e Text) (pEq "hoge") <<< gIn' ["foo", "bar"] <<< gIn' [] $. vertices' [] $ source "g"
    toGremlin gt `shouldBe` "g.V().in().in(\"foo\",\"bar\").has(\"name\",eq(\"hoge\"))"

spec_has :: Spec
spec_has = do
  describe "gHas1" $ do
    specify "IsString Key" $ do
      toGremlin (source "g" & vertices' [] &. gHas1 "foo") `shouldBe` "g.V().has(\"foo\")"
  describe "gHas2" $ do
    specify "IsString Key and P" $ do
      toGremlin (source "g" & vertices' [] &. gHas2 ("name" :: Key e Text) (pNeq "hoge"))
        `shouldBe` "g.V().has(\"name\",neq(\"hoge\"))"
  describe "gHasLabel" $ do
    specify "P" $ do
      toGremlin (source "g" & edges' [] &. gHasLabel (pNeq "friends_to"))
        `shouldBe` "g.E().hasLabel(neq(\"friends_to\"))"
  describe "gHasId" $ do
    specify "P" $ do
      toGremlin (source "g" & vertices' [] &. gHasId (pInside (unsafeGreskell "10") (unsafeGreskell "20")))
        `shouldBe` "g.V().hasId(inside(10,20))"
  describe "gHasKey" $ do
    specify "P" $ do
      pendingWith "TODO: we need .property step to test .hasKey step."
  describe "gHasValue" $ do
    specify "P" $ do
      pendingWith "TODO: we need .property step to test .hasValue step."

-- TODO:
-- あとはPとPredicateメソッドのテストも。

