{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Eta reduce" #-}

module Interface.Widget.Internal.FileDetail (
  widget,
  tagTextNodeKey,
) where

import Control.Lens ((^.))
import Data.Event (
  FileSelectionEvent (RenameFile),
  FocusedFileEvent (
    AppendTagText,
    CommitTagText,
    DeleteTag,
    MoveTag,
    NextTagHist,
    PrevTagHist,
    ResetTagHistIndex,
    TagFile,
    ToggleFocusedFilePaneVisibility
  ),
  TaggerEvent (DoFileSelectionEvent, DoFocusedFileEvent, IOEvent),
 )
import qualified Data.HashSet as HS
import Data.HierarchyMap (HierarchyMap)
import qualified Data.HierarchyMap as HM
import qualified Data.List as L
import Data.Model (
  HasFileInfoRenameText (fileInfoRenameText),
  HasFileSelectionInfoMap (fileSelectionInfoMap),
  HasFileSelectionModel (fileSelectionModel),
  HasFocusedFile (focusedFile),
  HasFocusedFileModel (focusedFileModel),
  HasFocusedFileVis (focusedFileVis),
  HasTagText (tagText),
  TaggerModel,
  fileInfoAt,
  focusedFileDefaultRecordKey,
 )
import Data.Model.Shared (Visibility (VisibilityLabel), hasVis)
import Data.Text (Text)
import qualified Data.Text as T
import Database.Tagger (
  ConcreteTag (ConcreteTag, concreteTagDescriptor, concreteTagId),
  ConcreteTaggedFile (ConcreteTaggedFile, concreteTaggedFile),
  Descriptor (Descriptor, descriptor),
  File (fileId, filePath),
  RecordKey,
  Tag,
 )
import Interface.Theme (yuiBlue, yuiLightPeach, yuiPeach, yuiRed)
import Interface.Widget.Internal.Core (
  defaultElementOpacity,
  defaultOpacityModulator,
  modulateOpacity,
  styledButton_,
  withNodeKey,
  withNodeVisible,
  withStyleBasic,
 )
import Interface.Widget.Internal.Type (TaggerWidget)
import Monomer (
  CmbAcceptTab (acceptTab),
  CmbAlignLeft (alignLeft),
  CmbAlignTop (alignTop),
  CmbBgColor (bgColor),
  CmbBorder (border),
  CmbBorderB (borderB),
  CmbMaxHeight (maxHeight),
  CmbOnChange (onChange),
  CmbPaddingR (paddingR),
  CmbResizeFactor (resizeFactor),
  CmbStyleHover (styleHoverSet),
  CmbTextColor (textColor),
  CmbWheelRate (wheelRate),
  CmbWidth (width),
  WidgetNode,
  black,
  box_,
  buttonD_,
  draggable,
  dropTargetStyle,
  dropTarget_,
  hstack_,
  keystroke_,
  label,
  label_,
  separatorLine,
  spacer,
  spacer_,
  textArea_,
  textField_,
  vscroll_,
  vstack,
  vstack_,
  zstack_,
 )

widget :: TaggerModel -> TaggerWidget
widget m = detailPane m

detailPane :: TaggerModel -> TaggerWidget
detailPane m =
  hstack_
    []
    [ separatorLine
    , detailPaneTagsWidget m
    ]

detailPaneTagsWidget :: TaggerModel -> TaggerWidget
detailPaneTagsWidget
  m@( (^. focusedFileModel . focusedFile) ->
        (ConcreteTaggedFile _ hm)
      ) =
    withStyleBasic
      [paddingR 20]
      $ vstack_
        []
        [ filePathWidget m
        , separatorLine
        , vstack
            [ vscroll_ [wheelRate 50] $
                vstack
                  [ metaLeaves
                      hm
                      ( L.sortOn (descriptor . concreteTagDescriptor)
                          . filter
                            ( \x ->
                                HM.metaMember x hm
                                  && not (HM.infraMember x hm)
                            )
                          . HM.keys
                          $ hm
                      )
                  , spacer_ [resizeFactor (-1)]
                  , nullMemberLeaves
                      ( L.sortOn (descriptor . concreteTagDescriptor)
                          . filter
                            ( \x ->
                                not (HM.metaMember x hm)
                                  && not (HM.infraMember x hm)
                            )
                          . HM.keys
                          $ hm
                      )
                  ]
            , tagTextField
            , deleteTagZone
            ]
        ]

filePathWidget :: TaggerModel -> TaggerWidget
filePathWidget m =
  hstack_
    []
    [ withNodeVisible
        ( focusedFileDefaultRecordKey
            /= (fileId . concreteTaggedFile $ m ^. focusedFileModel . focusedFile)
        )
        $ styledButton_
          [resizeFactor (-1)]
          "Rename"
          ( DoFocusedFileEvent
              (ToggleFocusedFilePaneVisibility fileRenameModeVis)
          )
    , zstack_
        []
        [ withNodeVisible (not $ isFileRenameMode m) $
            label_
              (filePath . concreteTaggedFile $ m ^. focusedFileModel . focusedFile)
              [resizeFactor (-1)]
        , withNodeVisible (isFileRenameMode m)
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
            . withStyleBasic
              [ bgColor
                  . modulateOpacity
                    (defaultElementOpacity - defaultOpacityModulator)
                  $ yuiLightPeach
              ]
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

fileRenameModeVis :: Text
fileRenameModeVis = "file-rename"

isFileRenameMode :: TaggerModel -> Bool
isFileRenameMode m =
  (m ^. focusedFileModel . focusedFileVis)
    `hasVis` VisibilityLabel fileRenameModeVis
{-# INLINE isFileRenameMode #-}

nullMemberLeaves ::
  Traversable t =>
  t ConcreteTag ->
  WidgetNode TaggerModel TaggerEvent
nullMemberLeaves members =
  withStyleBasic [borderB 1 black]
    . vstack_ []
    $ ( \ct@(ConcreteTag tk (Descriptor _ dp) _) ->
          subTagDropTarget tk
            . box_ [alignLeft, alignTop]
            . draggable ct
            $ label dp
      )
      <$> members

metaLeaves ::
  HierarchyMap ConcreteTag ->
  [ConcreteTag] ->
  WidgetNode TaggerModel TaggerEvent
metaLeaves hm members =
  vstack_ [] . L.intersperse spacer $
    (flip metaLeaf hm <$> members)

metaLeaf ::
  ConcreteTag ->
  HierarchyMap ConcreteTag ->
  TaggerWidget
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

metaTagLeafSpacer :: TaggerWidget
metaTagLeafSpacer = spacer_ [width 20]
{-# INLINE metaTagLeafSpacer #-}

subTagDropTarget ::
  RecordKey Tag ->
  TaggerWidget ->
  TaggerWidget
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

deleteTagZone :: TaggerWidget
deleteTagZone =
  dropTarget_
    (DoFocusedFileEvent . DeleteTag . concreteTagId)
    [dropTargetStyle [border 1 yuiRed]]
    . flip styleHoverSet []
    . withStyleBasic
      [ bgColor
          . modulateOpacity
            (defaultElementOpacity - defaultOpacityModulator)
          $ yuiLightPeach
      , border 1
          . modulateOpacity
            (defaultElementOpacity - defaultOpacityModulator)
          $ yuiPeach
      ]
    $ buttonD_ "Delete" [resizeFactor (-1)]

tagTextNodeKey :: Text
tagTextNodeKey = "tag-text-field"

tagTextField :: TaggerWidget
tagTextField =
  keystroke_
    [ ("Shift-Enter", DoFocusedFileEvent CommitTagText)
    , ("Shift-Up", DoFocusedFileEvent NextTagHist)
    , ("Shift-Down", DoFocusedFileEvent PrevTagHist)
    ]
    []
    . dropTarget_
      (DoFocusedFileEvent . AppendTagText . descriptor . concreteTagDescriptor)
      [dropTargetStyle [border 1 yuiRed]]
    . dropTarget_
      (DoFocusedFileEvent . AppendTagText . descriptor)
      [dropTargetStyle [border 1 yuiBlue]]
    . withNodeKey tagTextNodeKey
    . withStyleBasic
      [ bgColor
          . modulateOpacity
            (defaultElementOpacity - defaultOpacityModulator)
          $ yuiLightPeach
      , maxHeight 250
      ]
    $ textArea_
      (focusedFileModel . tagText)
      [ onChange
          ( \t ->
              if T.null . T.strip $ t
                then DoFocusedFileEvent ResetTagHistIndex
                else
                  IOEvent
                    ()
          )
      , acceptTab
      ]
