{-# LANGUAGE TypeFamilies, OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}
-- |
-- Module: Data.Greskell.Graph
-- Description: Haskell counterpart of Gremlin graph structure data types.
-- Maintainer: Toshio Ito <debug.ito@gmail.com>
--
-- 
module Data.Greskell.Graph
       ( -- * TinkerPop graph structure API
         Element(..),
         Vertex,
         Edge,
         Property(..),
         T,
         tId,
         tKey,
         tLabel,
         tValue,
         -- * Extended API
         Key(..),
         -- * Concrete data types
         AesonVertex,
         AesonEdge,
         AesonProperty,
         AesonVertexProperty
       ) where

import Control.Applicative (empty, (<$>), (<*>))
import Data.Aeson (Value(..), FromJSON(..), (.:))
import Data.String (IsString(..))
import Data.Text (Text)

import Data.Greskell.Greskell
  ( Greskell, unsafeGreskellLazy, string,
    ToGreskell(..)
  )

-- | @Element@ interface in a TinkerPop graph.
class Element e where
  type ElementID e
  -- ^ ID type of the 'Element'
  type ElementProperty e :: * -> *
  -- ^ Property type of the 'Element'. It should be of 'Property'
  -- class.
  elementId :: e -> ElementID e
  elementLabel :: e -> Text

-- | @Vertex@ interface in a TinkerPop graph.
class (Element v) => Vertex v

-- | @Edge@ interface in a TinkerPop graph.
class (Element e) => Edge e

-- | @Property@ interface in a TinkerPop graph.
class Property p where
  propertyKey :: p v -> Text
  propertyValue :: p v -> v

-- | @org.apache.tinkerpop.gremlin.structure.T@ enum.
--
-- 'T' is a token to get data @b@ from an Element @a@.
data T a b

-- | @T.id@ token.
tId :: Element a => Greskell (T a (ElementID a))
tId = unsafeGreskellLazy "id"

-- | @T.key@ token.
tKey :: (Element (p v), Property p) => Greskell (T (p v) Text)
tKey = unsafeGreskellLazy "key"

-- | @T.label@ token.
tLabel :: Element a => Greskell (T a Text)
tLabel = unsafeGreskellLazy "label"

-- | @T.value@ token.
tValue :: (Element (p v), Property p) => Greskell (T (p v) v)
tValue = unsafeGreskellLazy "value"


-- | A property key accessing value @b@ in an Element @a@. In Gremlin,
-- it's just a String type.
newtype Key a b = Key { unKey :: Greskell Text }
                deriving (Show,Eq)

-- | Unsafely convert the value type @b@.
instance Functor (Key a) where
  fmap _ (Key t) = Key t

-- | Gremlin String literal as a 'Key'.
instance IsString (Key a b) where
  fromString = Key . fromString

-- | Unwrap 'Key' constructor.
instance ToGreskell (Key a b) where
  type GreskellReturn (Key a b) = Text
  toGreskell = unKey

-- | General vertex type you can use for 'Vertex' class, based on
-- aeson data types.
data AesonVertex

-- | TODO: 'Element' methods are not implemented yet.
instance Element AesonVertex where
  type ElementID AesonVertex = Value
  type ElementProperty AesonVertex = AesonVertexProperty
  elementId = undefined
  elementLabel = undefined

instance Vertex AesonVertex

-- | General edge type you can use for 'Edge' class, based on aeson
-- data types.
data AesonEdge

-- | TODO: 'Element' methods are not implemented yet.
instance Element AesonEdge where
  type ElementID AesonEdge = Value
  type ElementProperty AesonEdge = AesonProperty
  elementId = undefined
  elementLabel = undefined

instance Edge AesonEdge

-- | General simple property type you can use for 'Property' class,
-- based on aeson data types.
data AesonProperty v =
  AesonProperty
  { aPropertyKey :: Text,
    aPropertyValue :: v
  }
  deriving (Show,Eq,Ord)

-- | Parse Property of GraphSON 1.0.
instance FromJSON v => FromJSON (AesonProperty v) where
  parseJSON (Object o) =
    AesonProperty <$> (o .: "key") <*> (o .: "value")
  parseJSON _ = empty

instance Property AesonProperty where
  propertyKey = aPropertyKey
  propertyValue = aPropertyValue


-- | General vertex property type you can use for VertexProperty,
-- based on aeson data types.
data AesonVertexProperty v

-- | TODO: 'Element' methods are not implemented yet.
instance Element (AesonVertexProperty v) where
  type ElementID (AesonVertexProperty v) = Value
  type ElementProperty (AesonVertexProperty v) = AesonProperty
  elementId = undefined
  elementLabel = undefined

-- | TODO: 'Property' methods are not implemented yet.
instance Property AesonVertexProperty where
  propertyKey = undefined
  propertyValue = undefined


-- -- We could define the following constraint synonym with
-- -- ConstraintKinds extension, although its semantics is not exactly
-- -- correct..
-- type VertexProperty p v = (Element (p v), Property p)
