{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Redundant flip" #-}

module Interface.Widget.Internal (
  TaggerWidget,
  hidePossibleUIVis,
  fileSelectionWidget,
  fileSelectionOperationWidget,
  queryTextFieldKey,
  tagTextNodeKey,
  zstackTaggingWidgetVis,
  zstackQueryWidgetVis,
  focusedFileWidget,
  descriptorTreeWidget,
  taggerInfoWidget,
) where

import Control.Lens
import Data.Event
import qualified Data.HashSet as HS
import qualified Data.HierarchyMap as HM
import qualified Data.List as L
import Data.Model
import Data.Model.Shared
import qualified Data.OccurrenceHashMap as OHM
import qualified Data.Ord as O
import qualified Data.Sequence as Seq
import Data.Tagger
import Data.Text (Text)
import qualified Data.Text as T
import Database.Tagger.Type
import Interface.Theme
import Monomer
import Monomer.Graphics.Lens

type TaggerWidget = WidgetNode TaggerModel TaggerEvent

hidePossibleUIVis :: Text
hidePossibleUIVis = "hide-possible-elements"

{-
 _____ ___ _     _____
|  ___|_ _| |   | ____|
| |_   | || |   |  _|
|  _|  | || |___| |___
|_|   |___|_____|_____|

 ____  _____ _     _____ ____ _____ ___ ___  _   _
/ ___|| ____| |   | ____/ ___|_   _|_ _/ _ \| \ | |
\___ \|  _| | |   |  _|| |     | |  | | | | |  \| |
 ___) | |___| |___| |__| |___  | |  | | |_| | |\  |
|____/|_____|_____|_____\____| |_| |___\___/|_| \_|

__        _____ ____   ____ _____ _____
\ \      / /_ _|  _ \ / ___| ____|_   _|
 \ \ /\ / / | || | | | |  _|  _|   | |
  \ V  V /  | || |_| | |_| | |___  | |
   \_/\_/  |___|____/ \____|_____| |_|

-}

queryTextFieldKey :: Text
queryTextFieldKey = "queryTextField"

manageFileSelectionPane :: Text
manageFileSelectionPane = "manage-file-selection"

editFileMode :: Text
editFileMode = "edit-file"

fileSelectionWidget :: TaggerModel -> TaggerWidget
fileSelectionWidget m =
  vstack_
    []
    [ withStyleBasic [textCenter, paddingT 5, paddingB 5] $
        selectionSizeLabel m
    , withStyleBasic [paddingB 5] separatorLine
    , fileSelectionWidgetHeader
    , zstack_
        []
        [ withNodeVisible (not selectionIsVisible) $ tagListWidget m
        , withNodeVisible selectionIsVisible $ fileSelectionFileList m
        ]
    , fileSelectionManagePane m
    ]
 where
  selectionIsVisible =
    (m ^. fileSelectionModel . fileSelectionVis) `hasVis` VisibilityAlt
  fileSelectionWidgetHeader =
    hstack_
      []
      [ clearSelectionButton
      , setOpDrowpdown
      ]

fileSelectionOperationWidget :: TaggerModel -> TaggerWidget
fileSelectionOperationWidget _ =
  withStyleBasic
    [borderL 1 black, borderR 1 black]
    queryWidget
 where
  queryWidget =
    box_ [alignTop, alignCenter] $
      hstack_ [] [runQueryButton, queryTextField]
   where
    runQueryButton = styledButton "Search" (DoFileSelectionEvent Query)

fileSelectionFileList :: TaggerModel -> TaggerWidget
fileSelectionFileList m =
  vstack_
    []
    [ fileSelectionHeader
    , separatorLine
    , vscroll_ [wheelRate 50]
        . vstack_ []
        $ fmap fileSelectionLeaf (m ^. fileSelectionModel . selection)
    ]
 where
  fileSelectionHeader :: TaggerWidget
  fileSelectionHeader = hstack_ [] [toggleViewSelectionButton, shuffleSelectionButton]
  fileSelectionLeaf :: File -> TaggerWidget
  fileSelectionLeaf f@(File fk fp) =
    zstack_
      []
      [ withNodeVisible
          ( not isEditMode
          )
          . draggable f
          . withStyleBasic [textLeft]
          $ label_ fp []
      , withNodeVisible isEditMode editModeWidget
      ]
   where
    editModeWidget = hstack_ [] [removeFromSelectionButton, renameFileTextField, label "edit mode :P"]
     where
      renameFileTextField :: TaggerWidget
      renameFileTextField =
        keystroke_
          [("Enter", DoFileSelectionEvent . RenameFile $ fk)]
          [ignoreChildrenEvts]
          $ textField_
            ( fileSelectionModel
                . fileSelectionInfoMap
                . fileInfoAt (fromIntegral fk)
                . fileInfoRenameText
            )
            []
      removeFromSelectionButton =
        styledButton_
          [resizeFactorW (-1)]
          "-"
          (DoFileSelectionEvent (RemoveFileFromSelection fk))
    isEditMode =
      (m ^. fileSelectionModel . fileSelectionVis)
        `hasVis` VisibilityLabel editFileMode

tagListWidget :: TaggerModel -> TaggerWidget
tagListWidget m =
  vstack_
    []
    [ tagListHeader
    , separatorLine
    , vscroll_ [wheelRate 50] $
        vstack_ [] (tagListLeaf <$> sortedOccurrenceMapList)
    ]
 where
  tagListHeader =
    hstack_
      []
      [ tagListOrderCritCycleButton
      , tagListOrderDirCycleButton
      , toggleViewSelectionButton
      ]
  sortedOccurrenceMapList =
    let (OrderBy ordCrit ordDir) = m ^. fileSelectionModel . tagOrdering
        !occurrenceMapList = OHM.toList $ m ^. fileSelectionModel . tagOccurrences
     in case (ordCrit, ordDir) of
          (Alphabetic, Asc) -> L.sortOn (descriptor . fst) occurrenceMapList
          (Alphabetic, Desc) -> L.sortOn (O.Down . descriptor . fst) occurrenceMapList
          (Numeric, Asc) -> L.sortOn snd occurrenceMapList
          (Numeric, Desc) -> L.sortOn (O.Down . snd) occurrenceMapList
  tagListOrderCritCycleButton =
    let (OrderBy ordCrit _) = m ^. fileSelectionModel . tagOrdering
        btnText =
          case ordCrit of
            Alphabetic -> "ABC"
            Numeric -> "123"
     in styledButton_
          [resizeFactorW (-1)]
          btnText
          (DoFileSelectionEvent CycleTagOrderCriteria)
  tagListOrderDirCycleButton =
    let (OrderBy _ ordDir) = m ^. fileSelectionModel . tagOrdering
     in styledButton_
          [resizeFactor (-1)]
          (T.pack . show $ ordDir)
          (DoFileSelectionEvent CycleTagOrderDirection)
  tagListLeaf (d, n) =
    hgrid_
      []
      [ draggable d . label . descriptor $ d
      , withStyleBasic
          [paddingL 1.5, paddingR 1.5]
          separatorLine
      , label . T.pack . show $ n
      ]

fileSelectionManagePane :: TaggerModel -> TaggerWidget
fileSelectionManagePane m =
  vstack_
    []
    [ withNodeVisible
        fileSelectionManagePaneIsVisible
        addFilesWidget
    , withNodeVisible
        fileSelectionManagePaneIsVisible
        $ hstack_ [] [refreshFileSelectionButton, toggleFileEditMode]
    , styledButton_
        [resizeFactorW (-1)]
        "Manage"
        (DoFileSelectionEvent (TogglePaneVisibility manageFileSelectionPane))
    ]
 where
  fileSelectionManagePaneIsVisible =
    (m ^. fileSelectionModel . fileSelectionVis)
      `hasVis` VisibilityLabel manageFileSelectionPane

clearSelectionButton :: TaggerWidget
clearSelectionButton =
  styledButton_
    [resizeFactorW (-1)]
    "Clear"
    (DoFileSelectionEvent ClearSelection)

toggleViewSelectionButton :: TaggerWidget
toggleViewSelectionButton =
  styledButton_
    [resizeFactor (-1)]
    "View"
    (DoFileSelectionEvent ToggleSelectionView)

addFilesWidget :: TaggerWidget
addFilesWidget =
  keystroke
    [ ("Enter", DoFileSelectionEvent AddFiles)
    , ("Up", DoFileSelectionEvent NextAddFileHist)
    , ("Down", DoFileSelectionEvent PrevAddFileHist)
    ]
    $ hstack_
      []
      [ styledButton_ [resizeFactor (-1)] "Add" (DoFileSelectionEvent AddFiles)
      , textField_
          (fileSelectionModel . addFileText)
          [ onChange
              ( \t ->
                  if T.null t
                    then DoFileSelectionEvent ResetAddFileHistIndex
                    else IOEvent ()
              )
          ]
      ]

setOpDrowpdown :: TaggerWidget
setOpDrowpdown =
  dropdown
    (fileSelectionModel . setOp)
    [Union, Intersect, Difference]
    (flip label_ [resizeFactor (-1)] . T.pack . show)
    (flip label_ [resizeFactor (-1)] . T.pack . show)

selectionSizeLabel :: TaggerModel -> TaggerWidget
selectionSizeLabel m =
  flip label_ [resizeFactorW (-1)] $
    "In Selection: ("
      <> ( T.pack . show
            . Seq.length
            $ m ^. fileSelectionModel . selection
         )
      <> ")"

refreshFileSelectionButton :: TaggerWidget
refreshFileSelectionButton =
  styledButton_
    [resizeFactor (-1)]
    "Refresh"
    (DoFileSelectionEvent RefreshFileSelection)

toggleFileEditMode :: TaggerWidget
toggleFileEditMode =
  styledButton_
    [resizeFactor (-1)]
    "Edit"
    (DoFileSelectionEvent (TogglePaneVisibility editFileMode))

shuffleSelectionButton :: TaggerWidget
shuffleSelectionButton =
  styledButton_
    [resizeFactor (-1)]
    "Shuffle"
    (DoFileSelectionEvent ShuffleSelection)

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

tagTextNodeKey :: Text
tagTextNodeKey = "tag-text-field"

zstackTaggingWidgetVis :: Text
zstackTaggingWidgetVis = "show-tag-field"

zstackQueryWidgetVis :: Text
zstackQueryWidgetVis = "show-query-field"

focusedFileWidget :: TaggerModel -> TaggerWidget
focusedFileWidget m =
  box_ []
    . withStyleBasic [minHeight 300]
    $ hsplit_
      [splitIgnoreChildResize True, splitHandleSize 10]
      ( withStyleBasic [borderR 1 black] focusedFileMainPane
      , withNodeVisible
          (not $ (m ^. visibilityModel) `hasVis` VisibilityLabel hidePossibleUIVis)
          $ detailPane m
      )
 where
  focusedFileMainPane =
    zstack_
      [onlyTopActive_ False]
      [ dropTarget_
          (DoFocusedFileEvent . PutFile)
          [dropTargetStyle [border 3 yuiOrange]]
          . dropTarget_
            (\(Descriptor dk _) -> DoFocusedFileEvent (TagFile dk Nothing))
            [dropTargetStyle [border 3 yuiBlue]]
          . dropTarget_
            (DoFocusedFileEvent . UnSubTag . concreteTagId)
            [dropTargetStyle [border 1 yuiRed]]
          . withStyleBasic []
          . box_
            [ mergeRequired
                ( \_ m1 m2 ->
                    concreteTaggedFile (m1 ^. focusedFileModel . focusedFile)
                      /= concreteTaggedFile (m2 ^. focusedFileModel . focusedFile)
                )
            ]
          $ ( case m ^. focusedFileModel . renderability of
                RenderAsImage -> imagePreviewRender
                _ -> imagePreviewRender
            )
            (filePath . concreteTaggedFile $ (m ^. focusedFileModel . focusedFile))
      , withNodeVisible
          ( not $
              (m ^. visibilityModel) `hasVis` VisibilityLabel hidePossibleUIVis
          )
          . box_
            [alignBottom, alignLeft, ignoreEmptyArea]
          $ vstack
            [ hstack [zstackNextImage, zstackTaggingWidget]
            , hstack [zstackPrevImage, zstackQueryWidget]
            ]
      ]
   where
    zstackNextImage =
      withStyleBasic [bgColor $ yuiLightPeach & a .~ 0.33] $
        styledButton_ [resizeFactor (-1)] "↑" (DoFileSelectionEvent CycleNextFile)
    zstackPrevImage =
      withStyleBasic [bgColor $ yuiLightPeach & a .~ 0.33] $
        styledButton_ [resizeFactor (-1)] "↓" (DoFileSelectionEvent CyclePrevFile)
    zstackQueryWidget :: TaggerWidget
    zstackQueryWidget =
      box_ [alignLeft, ignoreEmptyArea]
        . withStyleBasic [maxWidth 450]
        $ hstack_
          []
          [ vstack . (: []) . withStyleBasic [bgColor $ yuiLightPeach & a .~ 0.33] $
              styledButton_
                [resizeFactor (-1)]
                "Query"
                ( DoFocusedFileEvent
                    (ToggleFocusedFilePaneVisibility zstackQueryWidgetVis)
                )
          , withNodeVisible isVisible queryTextField
          ]
     where
      isVisible =
        (m ^. focusedFileModel . focusedFileVis)
          `hasVis` VisibilityLabel zstackQueryWidgetVis
    zstackTaggingWidget :: TaggerWidget
    zstackTaggingWidget =
      box_ [alignLeft, ignoreEmptyArea]
        . withStyleBasic [maxWidth 400]
        $ hstack
          [ vstack . (: []) . withStyleBasic [bgColor $ yuiLightPeach & a .~ 0.33] $
              styledButton_
                [resizeFactor (-1)]
                "Tag"
                ( DoFocusedFileEvent
                    (ToggleFocusedFilePaneVisibility zstackTaggingWidgetVis)
                )
          , withNodeVisible
              isVisible
              tagTextField
          ]
     where
      isVisible =
        (m ^. focusedFileModel . focusedFileVis)
          `hasVis` VisibilityLabel zstackTaggingWidgetVis

imagePreviewRender :: Text -> TaggerWidget
imagePreviewRender fp = image_ fp [fitEither, alignCenter]

detailPane :: TaggerModel -> TaggerWidget
detailPane m@((^. focusedFileModel . focusedFile) -> (ConcreteTaggedFile _ hm)) =
  hstack_
    []
    [ separatorLine
    , detailPaneTagsWidget
    ]
 where
  detailPaneTagsWidget =
    let metaMembers =
          L.sortOn (descriptor . concreteTagDescriptor)
            . filter (\x -> HM.metaMember x hm && not (HM.infraMember x hm))
            . HM.keys
            $ hm
        topNullMembers =
          L.sortOn (descriptor . concreteTagDescriptor)
            . filter
              ( \x ->
                  not (HM.metaMember x hm)
                    && not (HM.infraMember x hm)
              )
            . HM.keys
            $ hm
     in withStyleBasic
          [paddingR 20]
          $ vgrid_
            []
            [ vstack_
                []
                [ filePathWidget
                , separatorLine
                , vscroll_ [wheelRate 50] $
                    vstack
                      [ metaLeaves metaMembers
                      , spacer
                      , nullMemberLeaves topNullMembers
                      ]
                , separatorLine
                , deleteTagZone
                , separatorLine
                ]
            , withStyleBasic [paddingT 20] $
                vstack
                  [ separatorLine
                  , fileSelectionWidget m
                  ]
            ]
   where
    filePathWidget :: TaggerWidget
    filePathWidget =
      hstack_
        []
        [ withNodeVisible
            ( focusedFileDefaultRecordKey
                /= (fileId . concreteTaggedFile $ m ^. focusedFileModel . focusedFile)
            )
            $ styledButton
              "Rename"
              ( DoFocusedFileEvent
                  (ToggleFocusedFilePaneVisibility fileRenameModeVis)
              )
        , zstack_
            []
            [ withNodeVisible (not isFileRenameMode) $
                flip
                  label_
                  [resizeFactor (-1)]
                  (filePath . concreteTaggedFile $m ^. focusedFileModel . focusedFile)
            , withNodeVisible isFileRenameMode
                . keystroke_
                  [
                    ( "Enter"
                    , DoFileSelectionEvent
                        . RenameFile
                        $ ( fileId . concreteTaggedFile $
                              m ^. focusedFileModel . focusedFile
                          )
                    )
                  ]
                  []
                $ textField_
                  ( fileSelectionModel
                      . fileSelectionInfoMap
                      . fileInfoAt
                        ( fromIntegral
                            . fileId
                            . concreteTaggedFile
                            $ m ^. focusedFileModel . focusedFile
                        )
                      . fileInfoRenameText
                  )
                  []
            ]
        ]
     where
      fileRenameModeVis = "file-rename"
      isFileRenameMode =
        (m ^. focusedFileModel . focusedFileVis)
          `hasVis` VisibilityLabel fileRenameModeVis
    nullMemberLeaves topNullMembers =
      withStyleBasic [borderB 1 black]
        . vstack_ []
        $ ( \ct@(ConcreteTag tk (Descriptor _ dp) _) ->
              subTagDropTarget tk
                . box_ [alignLeft, alignTop]
                . draggable ct
                $ label dp
          )
          <$> topNullMembers
    metaLeaves :: [ConcreteTag] -> TaggerWidget
    metaLeaves metaMembers =
      vstack_ [] . L.intersperse spacer $
        (flip metaLeaf hm <$> metaMembers)
     where
      metaLeaf l@(ConcreteTag tk (Descriptor _ dp) _) hmap =
        let subtags =
              L.sortOn (descriptor . concreteTagDescriptor)
                . HS.toList
                $ HM.find l hmap
         in if null subtags
              then
                subTagDropTarget tk . box_ [alignLeft, alignTop]
                  . draggable l
                  $ label dp
              else
                vstack_
                  []
                  [ hstack_
                      []
                      [ subTagDropTarget tk
                          . box_ [alignLeft, alignTop]
                          . draggable l
                          . withStyleBasic [textColor yuiBlue]
                          $ label dp
                      , spacer
                      , label "{"
                      ]
                  , hstack_
                      []
                      [ metaTagLeafSpacer
                      , box_ [alignLeft, alignTop] $
                          vstack
                            ( flip metaLeaf hmap
                                <$> subtags
                            )
                      ]
                  , label "}"
                  ]
       where
        metaTagLeafSpacer = spacer_ [width 20]
    deleteTagZone :: TaggerWidget
    deleteTagZone =
      dropTarget_
        (DoFocusedFileEvent . DeleteTag . concreteTagId)
        [dropTargetStyle [border 1 yuiRed]]
        . flip styleHoverSet []
        . withStyleBasic [bgColor yuiLightPeach, border 1 yuiPeach]
        $ buttonD_ "Delete" [resizeFactor (-1)]
    subTagDropTarget tk =
      dropTarget_
        (\(Descriptor dk _) -> DoFocusedFileEvent (TagFile dk (Just tk)))
        [dropTargetStyle [border 1 yuiBlue]]
        . dropTarget_
          ( \ct ->
              DoFocusedFileEvent
                (MoveTag ct (Just tk))
          )
          [dropTargetStyle [border 1 yuiRed]]

tagTextField :: TaggerWidget
tagTextField =
  keystroke_
    [ ("Enter", DoFocusedFileEvent CommitTagText)
    , ("Up", DoFocusedFileEvent NextTagHist)
    , ("Down", DoFocusedFileEvent PrevTagHist)
    ]
    []
    . dropTarget_
      (DoFocusedFileEvent . AppendTagText . descriptor . concreteTagDescriptor)
      [dropTargetStyle [border 1 yuiRed]]
    . dropTarget_
      (DoFocusedFileEvent . AppendTagText . descriptor)
      [dropTargetStyle [border 1 yuiBlue]]
    . withNodeKey tagTextNodeKey
    . withStyleBasic [bgColor (yuiLightPeach & a .~ 0.33)]
    $ textField_
      (focusedFileModel . tagText)
      [ onChange
          ( \t ->
              if T.null t
                then DoFocusedFileEvent ResetTagHistIndex
                else
                  IOEvent
                    ()
          )
      ]

queryTextField :: TaggerWidget
queryTextField =
  keystroke_
    [ ("Enter", DoFileSelectionEvent Query)
    , ("Up", DoFileSelectionEvent NextQueryHist)
    , ("Down", DoFileSelectionEvent PrevQueryHist)
    ]
    []
    . dropTarget_
      (DoFileSelectionEvent . AppendQueryText . descriptor . concreteTagDescriptor)
      [dropTargetStyle [border 1 yuiRed]]
    . dropTarget_
      (DoFileSelectionEvent . AppendQueryText . filePath)
      [dropTargetStyle [border 1 yuiOrange]]
    . dropTarget_
      (DoFileSelectionEvent . AppendQueryText . descriptor)
      [dropTargetStyle [border 1 yuiBlue]]
    . withNodeKey queryTextFieldKey
    . withStyleBasic [bgColor (yuiLightPeach & a .~ 0.33)]
    $ textField_
      (fileSelectionModel . queryText)
      [ onChange
          ( \t ->
              if T.null t
                then DoFileSelectionEvent ResetQueryHistIndex
                else IOEvent ()
          )
      ]

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

editDescriptorVis :: Text
editDescriptorVis = "edit-descriptor"

manageDescriptorPaneVis :: Text
manageDescriptorPaneVis = "manage"

descriptorTreeWidget :: TaggerModel -> TaggerWidget
descriptorTreeWidget m =
  withNodeVisible
    ( not $
        (m ^. visibilityModel)
          `hasVis` VisibilityLabel hidePossibleUIVis
    )
    . withNodeKey "descriptorTree"
    $ keystroke_
      [("Ctrl-m", DoDescriptorTreeEvent (ToggleDescriptorTreeVisibility "manage"))]
      [ignoreChildrenEvts]
      $ vstack_
        []
        [ mainPane
        , altPane
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
      ]
   where
    mainPaneLeftButtonStack =
      vstack_
        []
        [ descriptorTreeRefreshBothButton
        , descriptorTreeRequestParentButton
        , descriptorTreeFixedRequestButton "#META#"
        ]
  altPane =
    withStyleBasic [border 1 black] $
      vstack_
        []
        [ descriptorTreeToggleVisButton
        , withNodeVisible
            ( (m ^. descriptorTreeModel . descriptorTreeVis)
                `hasVis` VisibilityLabel manageDescriptorPaneVis
            )
            $vstack
            [ insertDescriptorWidget
            , styledButton_
                [resizeFactor (-1)]
                "Edit"
                ( DoDescriptorTreeEvent
                    (ToggleDescriptorTreeVisibility editDescriptorVis)
                )
            ]
        ]

descriptorTreeFocusedNodeWidget :: TaggerModel -> TaggerWidget
descriptorTreeFocusedNodeWidget m =
  box_
    [ expandContent
    , mergeRequired
        ( \_ ((^. descriptorTreeModel) -> dm1) ((^. descriptorTreeModel) -> dm2) ->
            dm1 /= dm2
        )
    ]
    . withStyleBasic [borderR 1 black]
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
  nodeHeader =
    flip label_ [resizeFactor (-1)]
      . descriptor
      $ m ^. descriptorTreeModel . focusedNode

  createRelationDropTarget :: TaggerWidget -> TaggerWidget
  createRelationDropTarget =
    dropTarget_
      (DoDescriptorTreeEvent . CreateRelation (m ^. descriptorTreeModel . focusedNode))
      [dropTargetStyle [border 3 yuiBlue]]

descriptorTreeUnrelatedWidget :: TaggerModel -> TaggerWidget
descriptorTreeUnrelatedWidget m =
  box_
    [ expandContent
    , mergeRequired
        ( \_ ((^. descriptorTreeModel) -> dm1) ((^. descriptorTreeModel) -> dm2) ->
            dm1 /= dm2
        )
    ]
    . withStyleBasic [borderL 1 black]
    . createUnrelationDropTargetWidget
      $descriptorTreeUnrelatedWidgetBody
 where
  descriptorTreeUnrelatedWidgetBody :: TaggerWidget
  descriptorTreeUnrelatedWidgetBody =
    vstack_
      []
      [ flip label_ [resizeFactor (-1)] "Unrelated"
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
  insertButton =
    styledButton_
      [resizeFactor (-1)]
      "Insert"
      (DoDescriptorTreeEvent InsertDescriptor)

descriptorTreeLeaf :: TaggerModel -> Descriptor -> TaggerWidget
descriptorTreeLeaf
  model@((^. descriptorTreeModel . descriptorInfoMap) -> m)
  d@(Descriptor dk p) =
    let di = m ^. descriptorInfoAt (fromIntegral dk)
     in box_ [alignLeft] $
          zstack_
            []
            [ withNodeVisible
                ( not $
                    (model ^. descriptorTreeModel . descriptorTreeVis)
                      `hasVis` VisibilityLabel editDescriptorVis
                )
                $ mainDescriptorLeafPageWidget di
            , withNodeVisible
                ( (model ^. descriptorTreeModel . descriptorTreeVis)
                    `hasVis` VisibilityLabel editDescriptorVis
                )
                editDescriptorLeafPageWidget
            ]
   where
    mainDescriptorLeafPageWidget di =
      hstack_
        []
        [ draggable d
            . box_ [alignLeft]
            . withStyleHover [border 1 yuiOrange, bgColor yuiLightPeach]
            . withStyleBasic
              [ textColor (if di ^. descriptorIsMeta then yuiBlue else black)
              , textLeft
              ]
            $ button p (DoDescriptorTreeEvent (RequestFocusedNode p))
        ]
    editDescriptorLeafPageWidget =
      hstack_
        []
        [ box_ [alignLeft]
            . keystroke_
              [("Enter", DoDescriptorTreeEvent (UpdateDescriptor dk))]
              []
            $ textField_
              ( descriptorTreeModel
                  . descriptorInfoMap
                  . descriptorInfoAt (fromIntegral dk)
                  . renameText
              )
              []
        , box_ [alignLeft]
            . withStyleHover [bgColor yuiRed, textColor white]
            . withStyleBasic [textColor yuiRed]
            $ button "Delete" (DoDescriptorTreeEvent (DeleteDescriptor d))
        ]

descriptorTreeToggleVisButton :: TaggerWidget
descriptorTreeToggleVisButton =
  styledButton_
    [resizeFactor (-1)]
    "Manage Descriptors"
    (DoDescriptorTreeEvent (ToggleDescriptorTreeVisibility "manage"))

descriptorTreeFixedRequestButton :: Text -> TaggerWidget
descriptorTreeFixedRequestButton t =
  styledButton_
    [resizeFactor (-1)]
    "Top"
    (DoDescriptorTreeEvent . RequestFocusedNode $ t)

descriptorTreeRequestParentButton :: TaggerWidget
descriptorTreeRequestParentButton =
  styledButton_
    [resizeFactor (-1)]
    "Up"
    (DoDescriptorTreeEvent RequestFocusedNodeParent)

descriptorTreeRefreshBothButton :: TaggerWidget
descriptorTreeRefreshBothButton =
  styledButton_
    [resizeFactor (-1)]
    "Refresh"
    (DoDescriptorTreeEvent RefreshBothDescriptorTrees)

styledButton :: Text -> TaggerEvent -> TaggerWidget
styledButton t e =
  withStyleHover [bgColor yuiYellow, border 1 yuiOrange]
    . withStyleBasic [bgColor yuiLightPeach, border 1 yuiPeach]
    $ button t e

styledButton_ ::
  [ButtonCfg TaggerModel TaggerEvent] ->
  Text ->
  TaggerEvent ->
  TaggerWidget
styledButton_ opts t e =
  withStyleHover [bgColor yuiYellow, border 1 yuiOrange]
    . withStyleBasic [bgColor yuiLightPeach, border 1 yuiPeach]
    $ button_ t e opts

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

withNodeKey :: Text -> TaggerWidget -> TaggerWidget
withNodeKey = flip nodeKey

descriptorIsMetaInInfoMap :: TaggerModel -> Descriptor -> Bool
descriptorIsMetaInInfoMap
  ((^. descriptorTreeModel . descriptorInfoMap) -> m)
  (Descriptor (fromIntegral -> dk) _) = m ^. descriptorInfoAt dk . descriptorIsMeta

{-
 _____  _    ____  ____ _____ ____
|_   _|/ \  / ___|/ ___| ____|  _ \
  | | / _ \| |  _| |  _|  _| | |_) |
  | |/ ___ \ |_| | |_| | |___|  _ <
  |_/_/   \_\____|\____|_____|_| \_\

 ___ _   _ _____ ___
|_ _| \ | |  ___/ _ \
 | ||  \| | |_ | | | |
 | || |\  |  _|| |_| |
|___|_| \_|_|   \___/

__        _____ ____   ____ _____ _____
\ \      / /_ _|  _ \ / ___| ____|_   _|
 \ \ /\ / / | || | | | |  _|  _|   | |
  \ V  V /  | || |_| | |_| | |___  | |
   \_/\_/  |___|____/ \____|_____| |_|
-}

taggerInfoWidget :: TaggerModel -> TaggerWidget
taggerInfoWidget m@((^. taggerInfoModel) -> tim) =
  withNodeVisible
    ( not $
        (m ^. visibilityModel)
          `hasVis` VisibilityLabel hidePossibleUIVis
    )
    . box_ [alignMiddle]
    $ vstack $
      withStyleBasic [paddingT 2.5, paddingB 2.5]
        <$> ( [ flip label_ [resizeFactor (-1)] $ tim ^. message
              , flip label_ [resizeFactor (-1)] $ tim ^. versionMessage
              ]
                ++ ( (\(h, t) -> label_ (h <> ": " <> (tim ^. t)) [resizeFactor (-1)])
                      <$> [ ("In Directory", workingDirectory)
                          , ("Version", version)
                          , ("Last Accessed", lastAccessed)
                          , ("Last Saved", lastSaved)
                          ]
                   )
            )