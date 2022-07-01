{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}

module Interface.Widget.Internal (
  TaggerWidget,
  focusedFileWidget,
  descriptorTreeWidget,
) where

import Control.Lens
import Data.Config
import Data.Event
import qualified Data.List as L
import Data.Model
import Data.Model.Shared
import Data.Text (Text)
import Database.Tagger.Type
import Interface.Theme
import Monomer

type TaggerWidget = WidgetNode TaggerModel TaggerEvent

{-
 _____ ___   ____ _   _ ____  _____ ____
|  ___/ _ \ / ___| | | / ___|| ____|  _ \
| |_ | | | | |   | | | \___ \|  _| | | | |
|  _|| |_| | |___| |_| |___) | |___| |_| |
|_|   \___/ \____|\___/|____/|_____|____/

 _____ ___ _     _____
|  ___|_ _| |   | ____|
| |_   | || |   |  _|
|  _|  | || |___| |___
|_|   |___|_____|_____|

__        _____ ____   ____ _____ _____
\ \      / /_ _|  _ \ / ___| ____|_   _|
 \ \ /\ / / | || | | | |  _|  _|   | |
  \ V  V /  | || |_| | |_| | |___  | |
   \_/\_/  |___|____/ \____|_____| |_|

-}

focusedFileWidget :: TaggerModel -> TaggerWidget
focusedFileWidget m = filePreview
 where
  filePreview =
    withStyleBasic
      [ if not (m ^. isMassOperation)
          then border 1 yuiOrange
          else border 1 black
      ]
      $ ( case m ^. focusedFileModel . renderability of
            RenderAsImage -> imagePreviewRender
            _ -> imagePreviewRender
        )
        (filePath . concreteTaggedFile $ (m ^. focusedFileModel . focusedFile))

imagePreviewRender :: Text -> TaggerWidget
imagePreviewRender fp = image_ fp [fitEither, alignCenter]

{-
 ____  _____ ____   ____ ____  ___ ____ _____ ___  ____
|  _ \| ____/ ___| / ___|  _ \|_ _|  _ \_   _/ _ \|  _ \
| | | |  _| \___ \| |   | |_) || || |_) || || | | | |_) |
| |_| | |___ ___) | |___|  _ < | ||  __/ | || |_| |  _ <
|____/|_____|____/ \____|_| \_\___|_|    |_| \___/|_| \_\

 _____ ____  _____ _____
|_   _|  _ \| ____| ____|
  | | | |_) |  _| |  _|
  | | |  _ <| |___| |___
  |_| |_| \_\_____|_____|

__        _____ ____   ____ _____ _____
\ \      / /_ _|  _ \ / ___| ____|_   _|
 \ \ /\ / / | || | | | |  _|  _|   | |
  \ V  V /  | || |_| | |_| | |___  | |
   \_/\_/  |___|____/ \____|_____| |_|
-}

descriptorTreeWidget :: TaggerModel -> TaggerWidget
descriptorTreeWidget m =
  flip nodeKey "descriptorTree" $
    keystroke_
      [("Ctrl-m", DoDescriptorTreeEvent (ToggleDescriptorTreeVisibility "manage"))]
      [ignoreChildrenEvts]
      $ vstack_
        []
        [ mainPane
        , nodeVisible
            altPane
            (VisibilityLabel "manage" == (m ^. visibilityModel . descriptorTreeVis))
        ]
 where
  mainPane =
    vstack_
      []
      [ hstack_
          []
          [ mainPaneLeftButtonStack
          , hsplit_
              [ splitIgnoreChildResize True
              ]
              ( descriptorTreeFocusedNodeWidget m
              , descriptorTreeUnrelatedWidget m
              )
          ]
      , separatorLine
      , descriptorTreeToggleVisButton
      ]
   where
    mainPaneLeftButtonStack =
      vstack_
        []
        [ descriptorTreeRefreshBothButton
        , descriptorTreeRequestParentButton
        , descriptorTreeFixedRequestButton $
            m ^. conf . descriptorTreeConf . treeRootRequest
        ]
  altPane =
    withStyleBasic [border 1 black] $
      vstack_
        []
        [ insertDescriptorWidget
        , spacer
        , box_ [alignMiddle] deleteDescriptorWidget
        , spacer
        ]

descriptorTreeFocusedNodeWidget :: TaggerModel -> TaggerWidget
descriptorTreeFocusedNodeWidget m =
  withStyleBasic [borderR 1 black]
    . createRelationDropTarget
    $ descriptorTreeFocusedNodeWidgetBody
 where
  descriptorTreeFocusedNodeWidgetBody :: TaggerWidget
  descriptorTreeFocusedNodeWidgetBody =
    vstack_
      []
      [ nodeHeader
      , separatorLine
      , focusedTreeLeafWidget
      ]

  focusedTreeLeafWidget :: TaggerWidget
  focusedTreeLeafWidget =
    let focusedDescriptors = {-L.nub?-} m ^. descriptorTreeModel . focusedTree
        metaDescriptors =
          L.sort
            . filter
              (descriptorIsMetaInInfoMap m)
            $ focusedDescriptors
        infraDescriptors =
          L.sort
            . filter
              (not . descriptorIsMetaInInfoMap m)
            $ focusedDescriptors
     in vscroll_ [wheelRate 50] . vstack_ [] $
          descriptorTreeLeaf m
            <$> (metaDescriptors ++ infraDescriptors)

  nodeHeader :: TaggerWidget
  nodeHeader = label . descriptor $ m ^. descriptorTreeModel . focusedNode

  createRelationDropTarget :: TaggerWidget -> TaggerWidget
  createRelationDropTarget =
    dropTarget_
      (DoDescriptorTreeEvent . CreateRelation (m ^. descriptorTreeModel . focusedNode))
      [dropTargetStyle [border 3 yuiBlue]]

descriptorTreeUnrelatedWidget :: TaggerModel -> TaggerWidget
descriptorTreeUnrelatedWidget m =
  withStyleBasic [borderL 1 black]
    . createUnrelationDropTargetWidget
      $descriptorTreeUnrelatedWidgetBody
 where
  descriptorTreeUnrelatedWidgetBody :: TaggerWidget
  descriptorTreeUnrelatedWidgetBody =
    vstack_
      []
      [ label "Unrelated"
      , separatorLine
      , unrelatedTreeLeafWidget
      ]

  unrelatedTreeLeafWidget :: TaggerWidget
  unrelatedTreeLeafWidget =
    let unrelatedDescriptors = m ^. descriptorTreeModel . unrelated
        meta =
          L.sort
            . filter
              (descriptorIsMetaInInfoMap m)
            $ unrelatedDescriptors
        infra =
          L.sort
            . filter
              (not . descriptorIsMetaInInfoMap m)
            $ unrelatedDescriptors
     in vscroll_ [wheelRate 50] . vstack_ [] $ descriptorTreeLeaf m <$> (meta ++ infra)

  createUnrelationDropTargetWidget :: TaggerWidget -> TaggerWidget
  createUnrelationDropTargetWidget =
    dropTarget_
      (DoDescriptorTreeEvent . CreateRelation (m ^. descriptorTreeModel . unrelatedNode))
      [dropTargetStyle [border 3 yuiBlue]]

insertDescriptorWidget :: TaggerWidget
insertDescriptorWidget =
  keystroke_ [("Enter", DoDescriptorTreeEvent InsertDescriptor)] [] . hstack_ [] $
    [insertButton, textField_ (descriptorTreeModel . newDescriptorText) []]
 where
  insertButton = styledButton "Insert" (DoDescriptorTreeEvent InsertDescriptor)

deleteDescriptorWidget :: TaggerWidget
deleteDescriptorWidget =
  withStyleBasic [border 1 yuiRed]
    . dropTarget_
      (DoDescriptorTreeEvent . DeleteDescriptor)
      [dropTargetStyle [bgColor yuiRed, border 1 yuiYellow]]
    $ label "Delete"

descriptorTreeLeaf :: TaggerModel -> Descriptor -> TaggerWidget
descriptorTreeLeaf
  ((^. descriptorTreeModel . descriptorInfoMap) -> m)
  d@(Descriptor dk p) =
    let di = m ^. descriptorInfoMapAt (fromIntegral dk)
     in zstack_
          []
          [ withNodeVisible
              (VisibilityMain == di ^. descriptorInfoVis)
              $ hstack_
                []
                [ styledButton
                    "sus"
                    ( DoDescriptorTreeEvent
                        (ToggleDescriptorLeafVisibility dk)
                    )
                , draggable d
                    . withStyleHover [border 1 yuiOrange, bgColor yuiLightPeach]
                    . withStyleBasic
                      [ textColor (if di ^. descriptorIsMeta then yuiBlue else black)
                      , textLeft
                      ]
                    $ button p (DoDescriptorTreeEvent (RequestFocusedNode p))
                ]
          , withNodeVisible
              (VisibilityAlt == di ^. descriptorInfoVis)
              . hstack_ []
              $ [ styledButton
                    "Back"
                    (DoDescriptorTreeEvent (ToggleDescriptorLeafVisibility dk))
                , styledButton "Commit" (DoDescriptorTreeEvent (UpdateDescriptor dk))
                , keystroke_
                    [("Enter", DoDescriptorTreeEvent (UpdateDescriptor dk))]
                    []
                    $ textField_
                      ( descriptorTreeModel
                          . descriptorInfoMap
                          . descriptorInfoMapAt (fromIntegral dk)
                          . renameText
                      )
                      []
                ]
          ]

-- ((^. descriptorTreeModel . configuringLeaves) -> configuringLeavesSet)
-- (DescriptorWithInfo d@(Descriptor dk dName) isMeta) =
--   zstack_
--     []
--     [ withNodeVisible (not visibleConfiguration) $
--         hstack_
--           []
--           [ styledButton "-" (DoDescriptorTreeEvent (ConfigureDescriptorLeaf d))
--           , draggable d
--               . withStyleHover [border 1 yuiOrange, bgColor yuiLightPeach]
--               . withStyleBasic [textColor (if isMeta then yuiBlue else black), textLeft]
--               $ button dName (DoDescriptorTreeEvent (RequestFocusedNode dName))
--           ]
--     , withNodeVisible visibleConfiguration $
--         hstack_
--           []
--           [ styledButton "We have to go back" (DoDescriptorTreeEvent (ConfigureDescriptorLeaf d))
--           , textField (descriptorTreeModel . newDescriptorText)
--           ]
--     ]
--  where
--   visibleConfiguration = IntSet.member (fromIntegral dk) configuringLeavesSet

descriptorTreeToggleVisButton :: TaggerWidget
descriptorTreeToggleVisButton =
  styledButton
    "Manage Descriptors"
    (DoDescriptorTreeEvent (ToggleDescriptorTreeVisibility "manage"))

descriptorTreeFixedRequestButton :: Text -> TaggerWidget
descriptorTreeFixedRequestButton t =
  styledButton "Top" (DoDescriptorTreeEvent . RequestFocusedNode $ t)

descriptorTreeRequestParentButton :: TaggerWidget
descriptorTreeRequestParentButton =
  styledButton "Up" (DoDescriptorTreeEvent RequestFocusedNodeParent)

descriptorTreeRefreshBothButton :: TaggerWidget
descriptorTreeRefreshBothButton =
  styledButton
    "Refresh"
    (DoDescriptorTreeEvent RefreshBothDescriptorTrees)

styledButton :: Text -> TaggerEvent -> TaggerWidget
styledButton t e =
  withStyleHover [bgColor yuiYellow, border 1 yuiOrange]
    . withStyleBasic [bgColor yuiLightPeach, border 0 yuiPeach]
    $ button t e

withStyleBasic ::
  [StyleState] ->
  WidgetNode TaggerModel TaggerEvent ->
  WidgetNode TaggerModel TaggerEvent
withStyleBasic = flip styleBasic

withStyleHover ::
  [StyleState] ->
  WidgetNode TaggerModel TaggerEvent ->
  WidgetNode TaggerModel TaggerEvent
withStyleHover = flip styleHover

withNodeVisible :: Bool -> TaggerWidget -> TaggerWidget
withNodeVisible = flip nodeVisible

descriptorIsMetaInInfoMap :: TaggerModel -> Descriptor -> Bool
descriptorIsMetaInInfoMap
  ((^. descriptorTreeModel . descriptorInfoMap) -> m)
  (Descriptor (fromIntegral -> dk) _) = m ^. descriptorInfoMapAt dk . descriptorIsMeta