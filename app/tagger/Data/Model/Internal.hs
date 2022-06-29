{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use newtype instead of data" #-}

module Data.Model.Internal (
  TaggerModel (..),
  createTaggerModel,
  FocusedFileModel (..),
  focusedFileDefaultDataFile,
  DescriptorTreeModel (..),
  DescriptorWithInfo (..),
  createDescriptorTreeModel,
  VisibilityModel (..),
  Visibility (..),
  Renderability (..),
) where

import Data.Config.Internal (TaggerConfig)
import Data.HierarchyMap (empty)
import Data.Text (Text)
import Database.Tagger.Type

data TaggerModel = TaggerModel
  { _taggermodelConf :: TaggerConfig
  , _taggermodelDescriptorTreeModel :: DescriptorTreeModel
  , _taggermodelFocusedFileModel :: FocusedFileModel
  , _taggermodelVisibilityModel :: VisibilityModel
  , _taggermodelConnection :: TaggedConnection
  , _taggermodelIsMassOperation :: Bool
  , _taggermodelIsTagMode :: Bool
  , _taggerFileSelection :: [File]
  }
  deriving (Show, Eq)

createTaggerModel ::
  TaggerConfig ->
  TaggedConnection ->
  Descriptor ->
  Descriptor ->
  Text ->
  TaggerModel
createTaggerModel conf tc d unRelatedD defaultFilePath =
  TaggerModel
    { _taggermodelConf = conf
    , _taggermodelDescriptorTreeModel = createDescriptorTreeModel d unRelatedD
    , _taggermodelFocusedFileModel = createFocusedFileModel defaultFilePath
    , _taggermodelVisibilityModel = createVisibilityModel
    , _taggermodelConnection = tc
    , _taggermodelIsMassOperation = False
    , _taggermodelIsTagMode = True
    , _taggerFileSelection = []
    }

data FocusedFileModel = FocusedFileModel
  { _focusedfilemodelFocusedFile :: ConcreteTaggedFile
  , _focusedfilemodelRenderability :: Renderability
  }
  deriving (Show, Eq)

createFocusedFileModel :: Text -> FocusedFileModel
createFocusedFileModel fp =
  FocusedFileModel
    { _focusedfilemodelFocusedFile = ConcreteTaggedFile (File (-1) fp) empty
    , _focusedfilemodelRenderability = RenderingNotSupported
    }

focusedFileDefaultDataFile :: FilePath
focusedFileDefaultDataFile = "Yui_signature_SS.png"

data DescriptorTreeModel = DescriptorTreeModel
  { _descriptortreeUnrelatedNode :: Descriptor
  , _descriptortreeUnrelated :: [DescriptorWithInfo]
  , _descriptortreeFocusedNode :: Descriptor
  , _descriptortreeFocusedTree :: [DescriptorWithInfo]
  , _descriptortreeNewDescriptorText :: Text
  , _descriptortreeUpdateDescriptorFrom :: Maybe Descriptor
  , _descriptortreeUpdateDescriptorTo :: Text
  }
  deriving (Show, Eq)

data VisibilityModel = VisibilityModel
  { _visibilitymodelDescriptorTreeVis :: Visibility
  }
  deriving (Show, Eq)

createVisibilityModel :: VisibilityModel
createVisibilityModel =
  VisibilityModel
    { _visibilitymodelDescriptorTreeVis = VisibilityMain
    }

{- |
 Generic data type for changing visibility of a widget.

 Provides labels for visibility for a main page and alternate page and
 two additional constructors for either numbered pages or labeled pages.
-}
data Visibility
  = VisibilityMain
  | VisibilityAlt
  | VisibilityNum Int
  | VisibilityLabel Text
  deriving (Show, Eq)

data DescriptorWithInfo = DescriptorWithInfo
  { _descriptorwithInfoDescriptor :: Descriptor
  , _descriptorwithinfoDescriptorIsMeta :: Bool
  }
  deriving (Show, Eq)

data Renderability
  = RenderAsImage
  | RenderAsText
  | RenderingNotSupported
  deriving (Show, Eq, Enum)

{- |
 Create a new 'DescriptorTreeModel` with the given 'Descriptor` as the parent
 node.
-}
createDescriptorTreeModel :: Descriptor -> Descriptor -> DescriptorTreeModel
createDescriptorTreeModel n unrelatedD =
  DescriptorTreeModel
    { _descriptortreeUnrelatedNode = unrelatedD
    , _descriptortreeUnrelated = []
    , _descriptortreeFocusedNode = n
    , _descriptortreeFocusedTree = []
    , _descriptortreeNewDescriptorText = ""
    , _descriptortreeUpdateDescriptorFrom = Nothing
    , _descriptortreeUpdateDescriptorTo = ""
    }