{-# LANGUAGE OverloadedStrings #-}
{-# HLINT ignore "Use const" #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

module Interface.Handler (
  taggerEventHandler,
) where

import Control.Lens
import Control.Monad
import Control.Monad.Trans.Class
import Control.Monad.Trans.Except
import Control.Monad.Trans.Maybe
import Data.Event
import qualified Data.Foldable as F
import qualified Data.HashSet as HS
import Data.HierarchyMap (empty)
import qualified Data.HierarchyMap as HAM
import qualified Data.IntMap.Strict as IntMap
import Data.Maybe
import Data.Model
import Data.Model.Shared
import qualified Data.OccurrenceHashMap as OHM
import Data.Sequence (Seq ((:<|), (:|>)))
import qualified Data.Sequence as Seq
import Data.Tagger
import Data.Text (Text)
import qualified Data.Text as T
import Data.Version (showVersion)
import Database.Tagger
import Interface.Handler.Internal
import Interface.Widget.Internal (queryTextFieldKey, tagTextNodeKey, zstackQueryWidgetVis, zstackTaggingWidgetVis)
import Monomer
import Paths_tagger
import System.Directory (getCurrentDirectory)
import System.FilePath
import System.IO
import Tagger.Info (taggerVersion)
import Text.TaggerQL
import Util

taggerEventHandler ::
  WidgetEnv TaggerModel TaggerEvent ->
  WidgetNode TaggerModel TaggerEvent ->
  TaggerModel ->
  TaggerEvent ->
  [AppEventResponse TaggerModel TaggerEvent]
taggerEventHandler
  wenv
  node
  model@(_taggermodelConnection -> conn)
  event =
    case event of
      DoFocusedFileEvent e -> focusedFileEventHandler wenv node model e
      DoFileSelectionEvent e -> fileSelectionEventHandler wenv node model e
      DoDescriptorTreeEvent e -> descriptorTreeEventHandler wenv node model e
      DoTaggerInfoEvent e -> taggerInfoEventHandler wenv node model e
      FocusTagTextField ->
        if (model ^. focusedFileModel . focusedFileVis)
          `hasVis` VisibilityLabel zstackTaggingWidgetVis
          then [SetFocusOnKey . WidgetKey $ tagTextNodeKey]
          else
            [ Event
                ( DoFocusedFileEvent
                    (ToggleFocusedFilePaneVisibility zstackTaggingWidgetVis)
                )
            , SetFocusOnKey . WidgetKey $ tagTextNodeKey
            ]
      FocusQueryTextField ->
        if (model ^. focusedFileModel . focusedFileVis)
          `hasVis` VisibilityLabel zstackQueryWidgetVis
          then [SetFocusOnKey . WidgetKey $ queryTextFieldKey]
          else
            [ Event
                ( DoFocusedFileEvent
                    ( ToggleFocusedFilePaneVisibility
                        zstackQueryWidgetVis
                    )
                )
            , SetFocusOnKey . WidgetKey $ queryTextFieldKey
            ]
      TaggerInit ->
        [ Event (DoDescriptorTreeEvent DescriptorTreeInit)
        , Task
            ( DoTaggerInfoEvent . PutWorkingDirectory
                <$> (T.pack <$> getCurrentDirectory)
            )
        , Task
            ( DoTaggerInfoEvent . PutLastAccessed <$> do
                la <- runMaybeT $ getLastAccessed conn
                maybe (return "never") return la
            )
        , Task
            ( DoTaggerInfoEvent . PutLastSaved <$> do
                la <- runMaybeT $ getLastSaved conn
                maybe (return "never") return la
            )
        , Model $
            model & taggerInfoModel . Data.Model.version
              .~ ( T.pack . showVersion $
                    taggerVersion
                 )
              & taggerInfoModel . message
              .~ "Thank you for using tagger!"
              & taggerInfoModel . versionMessage
              .~ "Released on ????/??/??"
        , Event
            ( DoFocusedFileEvent
                (ToggleFocusedFilePaneVisibility zstackQueryWidgetVis)
            )
        , Event FocusQueryTextField
        ]
      RefreshUI ->
        [ Event (DoDescriptorTreeEvent RefreshBothDescriptorTrees)
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]
      ToggleMainVisibility t ->
        [Model $ model & visibilityModel %~ (flip togglePaneVis . VisibilityLabel $ t)]
      ToggleTagMode -> [Model $ model & isTagMode %~ not]
      CloseConnection -> [Task (IOEvent <$> close conn)]
      IOEvent _ -> []
      ClearTextField (TaggerLens l) -> [Model $ model & l .~ ""]

fileSelectionEventHandler ::
  WidgetEnv TaggerModel TaggerEvent ->
  WidgetNode TaggerModel TaggerEvent ->
  TaggerModel ->
  FileSelectionEvent ->
  [AppEventResponse TaggerModel TaggerEvent]
fileSelectionEventHandler
  _
  _
  model@(_taggermodelConnection -> conn)
  event =
    case event of
      AddFiles ->
        [ Task (IOEvent <$> addFiles conn (model ^. fileSelectionModel . addFileText))
        , Model $
            model & fileSelectionModel . addFileHistory
              %~ putHist (T.strip $ model ^. fileSelectionModel . addFileText)
        , Event (ClearTextField (TaggerLens (fileSelectionModel . addFileText)))
        ]
      AppendQueryText t ->
        [ Model $
            model
              & fileSelectionModel
                . queryText
              %~ flip
                T.append
                ( ( if T.null (model ^. fileSelectionModel . queryText)
                      then ""
                      else " "
                  )
                    <> t
                )
        ]
      ClearSelection ->
        [ Model $
            model & fileSelectionModel . selection .~ Seq.empty
              & fileSelectionModel . tagOccurrences .~ OHM.empty
              & fileSelectionModel . fileSelectionInfoMap .~ IntMap.empty
              & fileSelectionModel . fileSelectionVis .~ VisibilityMain
        ]
      CycleNextFile ->
        case model ^. fileSelectionModel . selection of
          Seq.Empty -> []
          _ :<| Seq.Empty -> []
          (f' :<| (f :<| fs)) ->
            [ Event . DoFocusedFileEvent . PutFile $ f
            , Model $ model & fileSelectionModel . selection .~ (f <| (fs |> f'))
            ]
      CycleNextSetOp -> [Model $ model & fileSelectionModel . setOp %~ next]
      CyclePrevFile ->
        case model ^. fileSelectionModel . selection of
          Seq.Empty -> []
          (Seq.Empty :|> _) -> []
          ((f' :<| fs) :|> f) ->
            [ Event . DoFocusedFileEvent . PutFile $ f
            , Model $ model & fileSelectionModel . selection .~ (f <| (f' <| fs))
            ]
      CyclePrevSetOp -> [Model $ model & fileSelectionModel . setOp %~ prev]
      CycleTagOrderCriteria ->
        [ Model $
            model & fileSelectionModel . tagOrdering
              %~ cycleOrderCriteria
        ]
      CycleTagOrderDirection ->
        [ Model $
            model & fileSelectionModel . tagOrdering
              %~ cycleOrderDir
        ]
      MakeFileSelectionInfoMap fseq ->
        [ let fiTuple (File fk fp) = (fromIntegral fk, FileInfo fp)
              m = F.toList $ fiTuple <$> fseq
           in Model $
                model
                  & fileSelectionModel
                    . fileSelectionInfoMap
                  .~ IntMap.fromList m
        ]
      NextAddFileHist ->
        [ Model $
            model
              & fileSelectionModel . addFileText
                .~ ( fromMaybe "" . getHist $
                      (model ^. fileSelectionModel . addFileHistory)
                   )
              & fileSelectionModel . addFileHistory %~ nextHist
        ]
      NextQueryHist ->
        [ Model $
            model
              & fileSelectionModel . queryText
                .~ (fromMaybe "" . getHist $ (model ^. fileSelectionModel . queryHistory))
              & fileSelectionModel . queryHistory %~ nextHist
        ]
      PrevAddFileHist ->
        [ Model $
            model
              & fileSelectionModel . addFileText
                .~ ( fromMaybe "" . getHist $
                      (model ^. fileSelectionModel . addFileHistory)
                   )
              & fileSelectionModel . addFileHistory %~ prevHist
        ]
      PrevQueryHist ->
        [ Model $
            model
              & fileSelectionModel . queryText
                .~ (fromMaybe "" . getHist $ (model ^. fileSelectionModel . queryHistory))
              & fileSelectionModel . queryHistory %~ prevHist
        ]
      PutFiles fs ->
        let currentSet =
              HS.fromList
                . F.toList
                $ model ^. fileSelectionModel . selection
            combFun =
              case model ^. fileSelectionModel . setOp of
                Union -> HS.union
                Intersect -> HS.intersection
                Difference -> HS.difference
            newSeq =
              Seq.fromList
                . HS.toList
                . combFun currentSet
                $ fs
         in [Event . DoFileSelectionEvent . PutFilesNoCombine $ newSeq]
      PutFilesNoCombine
        ( uncurry (Seq.><)
            . (\(x, y) -> (y, x))
            . Seq.breakl
              ( ( concreteTaggedFile $
                    model ^. focusedFileModel . focusedFile
                )
                  ==
              ) ->
            fseq
          ) ->
          [ Model $ model & fileSelectionModel . selection .~ fseq
          , Event
              ( DoFileSelectionEvent
                  (RefreshTagOccurrencesWith (fmap fileId fseq))
              )
          , Event (DoFileSelectionEvent . MakeFileSelectionInfoMap $ fseq)
          ]
            ++ ( case fseq of
                  Seq.Empty -> []
                  (f :<| _) -> [Event . DoFocusedFileEvent . PutFile $ f]
               )
      PutTagOccurrenceHashMap_ m ->
        [ Model $
            model
              & fileSelectionModel . tagOccurrences .~ m
        ]
      Query ->
        [ Task
            ( DoFileSelectionEvent
                . PutFiles
                <$> taggerQL
                  (TaggerQLQuery . T.strip $ model ^. fileSelectionModel . queryText)
                  conn
            )
        , Model $
            model & fileSelectionModel . queryHistory
              %~ putHist (T.strip $ model ^. fileSelectionModel . queryText)
        , Event (ClearTextField (TaggerLens (fileSelectionModel . queryText)))
        , Event (DoFileSelectionEvent ResetQueryHistIndex)
        ]
      RefreshSpecificFile fk ->
        [ Task
            ( do
                f <- runMaybeT $ queryForSingleFileByFileId fk conn
                maybe
                  (return . IOEvent $ ())
                  (return . DoFileSelectionEvent . RefreshSpecificFile_)
                  f
            )
        ]
      RefreshSpecificFile_ f@(File fk fp) ->
        let curSeq = model ^. fileSelectionModel . selection
            maybeIx = Seq.findIndexR ((==) fk . fileId) curSeq
         in [ Model $
                model & fileSelectionModel . selection
                  %~ maybe
                    (f <|)
                    (Seq.adjust (const f))
                    maybeIx
                  & fileSelectionModel . fileSelectionInfoMap
                    . fileInfoAt (fromIntegral fk)
                    .~ FileInfo fp
            , Event $ DoFileSelectionEvent RefreshTagOccurrences
            ]
      RefreshFileSelection ->
        [ Event (DoFileSelectionEvent RefreshTagOccurrences)
        , Event
            ( DoFileSelectionEvent
                ( MakeFileSelectionInfoMap $
                    model ^. fileSelectionModel . selection
                )
            )
        ]
      RefreshTagOccurrences ->
        [ Task
            ( DoFileSelectionEvent . PutTagOccurrenceHashMap_
                <$> getTagOccurrencesByFileKey
                  (map fileId . F.toList $ model ^. fileSelectionModel . selection)
                  conn
            )
        ]
      RemoveFileFromSelection fk ->
        let curSeq = model ^. fileSelectionModel . selection
            maybeIx = Seq.findIndexR ((==) fk . fileId) curSeq
         in maybe
              []
              ( \sindex ->
                  [ Event . DoFileSelectionEvent . PutFilesNoCombine
                      . flip Seq.deleteAt curSeq
                      $ sindex
                  ]
              )
              maybeIx
      RenameFile fk ->
        [ let newRenameText =
                model
                  ^. fileSelectionModel
                    . fileSelectionInfoMap
                    . fileInfoAt (fromIntegral fk)
                    . fileInfoRenameText
           in Task
                ( do
                    -- refetch the fk from the db,
                    -- to put the calculation in the MaybeT monad
                    result <- runMaybeT $ do
                      lift $ mvFile conn fk newRenameText
                      queryForSingleFileByFileId fk conn
                    maybe
                      (return $ IOEvent ())
                      (return . DoFileSelectionEvent . RefreshSpecificFile_)
                      result
                )
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]
      ResetAddFileHistIndex ->
        [ Model $
            model
              & fileSelectionModel . addFileHistory . historyIndex .~ 0
        ]
      ResetQueryHistIndex ->
        [ Model $
            model
              & fileSelectionModel . queryHistory . historyIndex .~ 0
        ]
      RefreshTagOccurrencesWith fks ->
        [ Task
            ( DoFileSelectionEvent . PutTagOccurrenceHashMap_
                <$> getTagOccurrencesByFileKey fks conn
            )
        ]
      ShuffleSelection ->
        [ Task
            ( DoFileSelectionEvent . PutFilesNoCombine
                <$> shuffleSequence (model ^. fileSelectionModel . selection)
            )
        ]
      TogglePaneVisibility t ->
        [ Model $
            model & fileSelectionModel . fileSelectionVis
              %~ flip togglePaneVis (VisibilityLabel t)
        ]
      ToggleSelectionView ->
        [ Model $
            model
              & fileSelectionModel
                . fileSelectionVis
              %~ toggleAltVis
        ]

focusedFileEventHandler ::
  WidgetEnv TaggerModel TaggerEvent ->
  WidgetNode TaggerModel TaggerEvent ->
  TaggerModel ->
  FocusedFileEvent ->
  [AppEventResponse TaggerModel TaggerEvent]
focusedFileEventHandler
  _
  _
  model@(_taggermodelConnection -> conn)
  event =
    case event of
      AppendTagText t ->
        [ Model $
            model
              & focusedFileModel
                . tagText
              %~ flip
                T.append
                ( ( if T.null (model ^. focusedFileModel . tagText)
                      then ""
                      else " "
                  )
                    <> t
                )
        ]
      CommitTagText ->
        [ Task
            ( IOEvent
                <$> taggerQLTag
                  (fileId . concreteTaggedFile $ model ^. focusedFileModel . focusedFile)
                  (TaggerQLTagStmnt . T.strip $ model ^. focusedFileModel . tagText)
                  conn
            )
        , Model $
            model & focusedFileModel . tagHistory
              %~ putHist (T.strip $ model ^. focusedFileModel . tagText)
        , Event (ClearTextField (TaggerLens $ focusedFileModel . tagText))
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]
      DeleteTag t ->
        [ Task (IOEvent <$> deleteTags [t] conn)
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]
      MoveTag
        (ConcreteTag oldTagKey (Descriptor dk dp) oldSubTagKey)
        newMaybeSubTagKey ->
          let (File fk _) =
                concreteTaggedFile $
                  model
                    ^. focusedFileModel . focusedFile
           in [ Task
                  ( IOEvent
                      <$> do
                        result <-
                          runExceptT $ do
                            withExceptT
                              (const "Cannot move tags of the default file.")
                              ( guard (fk /= focusedFileDefaultRecordKey) ::
                                  ExceptT String IO ()
                              )
                            withExceptT
                              ( const
                                  ( "Cannot move tag, "
                                      ++ T.unpack dp
                                      ++ ", to be a subtag of itself."
                                  )
                              )
                              ( guard
                                  ( maybe
                                      True
                                      ( \newSubTagKey ->
                                          not
                                            . HAM.isInfraTo newSubTagKey oldTagKey
                                            . HAM.mapHierarchyMap concreteTagId
                                            . concreteTaggedFileDescriptors
                                            $ model ^. focusedFileModel . focusedFile
                                      )
                                      newMaybeSubTagKey
                                  ) ::
                                  ExceptT String IO ()
                              )
                            withExceptT
                              ( const
                                  ( "Tag, "
                                      ++ T.unpack dp
                                      ++ ", is already subtagged to the destination."
                                  )
                              )
                              ( guard
                                  ( oldSubTagKey
                                      /= newMaybeSubTagKey
                                  ) ::
                                  ExceptT String IO ()
                              )
                            newTags <-
                              lift $
                                insertTags [(fk, dk, newMaybeSubTagKey)] conn
                            -- moving all old subtags to the new tag
                            -- or else they will be cascade deleted when the old tag is.
                            lift $ moveSubTags ((oldTagKey,) <$> newTags) conn
                            lift $ deleteTags [oldTagKey] conn
                        either (hPutStrLn stderr) return result
                  )
              , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
              ]
      NextTagHist ->
        [ Model $
            model
              & focusedFileModel . tagText
                .~ (fromMaybe "" . getHist $ (model ^. focusedFileModel . tagHistory))
              & focusedFileModel . tagHistory %~ nextHist
        ]
      PrevTagHist ->
        [ Model $
            model
              & focusedFileModel . tagText
                .~ (fromMaybe "" . getHist $ (model ^. focusedFileModel . tagHistory))
              & focusedFileModel . tagHistory %~ prevHist
        ]
      PutConcreteFile_ cf@(ConcreteTaggedFile (File _ fp) _) ->
        [ Model $
            model
              & focusedFileModel . focusedFile .~ cf
              & focusedFileModel . renderability .~ getRenderability fp
        ]
      PutFile (File fk _) ->
        [ Task
            ( do
                cft <- runMaybeT $ queryForConcreteTaggedFileWithFileId fk conn
                maybe
                  ( DoFocusedFileEvent . PutConcreteFile_ <$> do
                      defaultFile <- T.pack <$> getDataFileName focusedFileDefaultDataFile
                      return $
                        ConcreteTaggedFile
                          ( File
                              focusedFileDefaultRecordKey
                              defaultFile
                          )
                          empty
                  )
                  (return . DoFocusedFileEvent . PutConcreteFile_)
                  cft
            )
        ]
      RefreshFocusedFileAndSelection ->
        [ Event
            . DoFocusedFileEvent
            . PutFile
            . concreteTaggedFile
            $ model ^. focusedFileModel . focusedFile
        , Event . DoFileSelectionEvent $ RefreshFileSelection
        ]
      ResetTagHistIndex ->
        [ Model $
            model
              & focusedFileModel . tagHistory . historyIndex .~ 0
        ]
      -- Should:
      -- submit a tag in the db
      -- refresh the focused file detail widget
      -- refresh the selection if tag counts are displayed (?)
      TagFile dk mtk ->
        let (File fk _) =
              concreteTaggedFile $
                model
                  ^. focusedFileModel . focusedFile
         in [ Task
                ( IOEvent
                    <$> if or [fk == focusedFileDefaultRecordKey]
                      then hPutStrLn stderr "Cannot tag the default file."
                      else void $ insertTags [(fk, dk, mtk)] conn
                )
            , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
            ]
      ToggleFocusedFilePaneVisibility t ->
        [ Model $
            model & focusedFileModel . focusedFileVis
              %~ flip togglePaneVis (VisibilityLabel t)
        ]
      UnSubTag tk ->
        [ Task (IOEvent <$> unSubTags [tk] conn)
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]

-- this is kind of stupid but whatever.
getRenderability :: Text -> Renderability
getRenderability (takeExtension . T.unpack . T.toLower -> ext)
  | ext `elem` [".jpg", ".png", ".jfif", ".bmp", ".gif", ".jpeg"] = RenderAsImage
  | ext `elem` [".mp3", ".mp4", ".webm", ".mkv", ".m4v", ".wav", ".flac", ".ogg"] =
    RenderingNotSupported
  | otherwise = RenderAsText

descriptorTreeEventHandler ::
  WidgetEnv TaggerModel TaggerEvent ->
  WidgetNode TaggerModel TaggerEvent ->
  TaggerModel ->
  DescriptorTreeEvent ->
  [AppEventResponse TaggerModel TaggerEvent]
descriptorTreeEventHandler
  _
  _
  model@(_taggermodelConnection -> conn)
  event =
    case event of
      CreateRelation (Descriptor mk _) (Descriptor ik _) ->
        [ Task
            ( IOEvent <$> do
                insertDescriptorRelation mk ik conn
            )
        , Event (DoDescriptorTreeEvent RefreshBothDescriptorTrees)
        ]
      DeleteDescriptor (Descriptor dk _) ->
        [ Task (IOEvent <$> deleteDescriptors [dk] conn)
        , Event (DoDescriptorTreeEvent RefreshBothDescriptorTrees)
        ]
      DescriptorTreeInit ->
        [ Event (DoDescriptorTreeEvent RefreshUnrelated)
        , Event
            ( DoDescriptorTreeEvent
                ( RequestFocusedNode "#META#"
                )
            )
        , Task
            ( DoDescriptorTreeEvent . PutUnrelatedNode_
                <$> (head <$> queryForDescriptorByPattern "#UNRELATED#" conn)
            )
        ]
      InsertDescriptor ->
        [ Task
            ( IOEvent <$> do
                let newDesText =
                      T.words
                        . T.strip
                        $ model ^. descriptorTreeModel . newDescriptorText
                unless (null newDesText) (insertDescriptors newDesText conn)
            )
        , Event (DoDescriptorTreeEvent RefreshBothDescriptorTrees)
        , Event . ClearTextField $ TaggerLens (descriptorTreeModel . newDescriptorText)
        ]
      PutFocusedTree_ nodeName ds desInfoMap ->
        [ Model $
            model
              & descriptorTreeModel . focusedTree .~ ds
              & descriptorTreeModel . focusedNode .~ nodeName
              & descriptorTreeModel . descriptorInfoMap %~ IntMap.union desInfoMap
        ]
      PutUnrelated_ ds desInfoMap ->
        [ Model $
            model & descriptorTreeModel . unrelated .~ ds
              & descriptorTreeModel . descriptorInfoMap %~ IntMap.union desInfoMap
        ]
      PutUnrelatedNode_ d -> [Model $ model & descriptorTreeModel . unrelatedNode .~ d]
      RefreshBothDescriptorTrees ->
        [ Model $ model & descriptorTreeModel . descriptorInfoMap .~ IntMap.empty
        , Event (DoDescriptorTreeEvent RefreshUnrelated)
        , Event (DoDescriptorTreeEvent RefreshFocusedTree)
        ]
      RefreshFocusedTree ->
        [ Event
            ( DoDescriptorTreeEvent
                ( RequestFocusedNode . descriptor $
                    model ^. descriptorTreeModel . focusedNode
                )
            )
        ]
      RefreshUnrelated ->
        [ Task
            ( DoDescriptorTreeEvent . uncurry PutUnrelated_ <$> do
                unrelatedDs <- queryForDescriptorByPattern "#UNRELATED#" conn
                ds <-
                  concat
                    <$> mapM
                      (flip getInfraChildren conn . descriptorId)
                      unrelatedDs
                dsInfos <- IntMap.unions <$> mapM (toDescriptorInfo conn) ds
                return (ds, dsInfos)
            )
        ]
      RequestFocusedNode p ->
        [ Task
            ( DoDescriptorTreeEvent . (\(x, y, z) -> PutFocusedTree_ x y z) <$> do
                ds <- queryForDescriptorByPattern p conn
                d <-
                  maybe
                    (head <$> queryForDescriptorByPattern "#ALL#" conn)
                    return
                    . head'
                    $ ds
                ids <- getInfraChildren (descriptorId d) conn
                idsInfoMap <- IntMap.unions <$> mapM (toDescriptorInfo conn) ids
                return (d, ids, idsInfoMap)
            )
        ]
      RequestFocusedNodeParent ->
        [ Task
            ( do
                pd <-
                  runMaybeT $
                    getMetaParent
                      (descriptorId $ model ^. descriptorTreeModel . focusedNode)
                      conn
                maybe
                  (pure (IOEvent ()))
                  (pure . DoDescriptorTreeEvent . RequestFocusedNode . descriptor)
                  pd
            )
        ]
      ToggleDescriptorTreeVisibility l ->
        [ Model $
            model & descriptorTreeModel . descriptorTreeVis
              %~ flip togglePaneVis (VisibilityLabel l)
        ]
      UpdateDescriptor rkd@(RecordKey (fromIntegral -> dk)) ->
        let updateText =
              T.strip $
                model
                  ^. descriptorTreeModel
                    . descriptorInfoMap
                    . descriptorInfoAt dk
                    . renameText
         in if T.null updateText
              then []
              else
                [ Task
                    ( IOEvent
                        <$> updateDescriptors [(updateText, rkd)] conn
                    )
                , Event (DoDescriptorTreeEvent RefreshBothDescriptorTrees)
                ]

taggerInfoEventHandler ::
  WidgetEnv TaggerModel TaggerEvent ->
  WidgetNode TaggerModel TaggerEvent ->
  TaggerModel ->
  TaggerInfoEvent ->
  [AppEventResponse TaggerModel TaggerEvent]
taggerInfoEventHandler _ _ model e =
  case e of
    PutLastAccessed t -> [Model $ model & taggerInfoModel . lastAccessed .~ t]
    PutLastSaved t -> [Model $ model & taggerInfoModel . lastSaved .~ t]
    PutWorkingDirectory t -> [Model $ model & taggerInfoModel . workingDirectory .~ t]

toDescriptorInfo :: TaggedConnection -> Descriptor -> IO (IntMap.IntMap DescriptorInfo)
toDescriptorInfo tc (Descriptor dk p) = do
  let consDes b = DescriptorInfo b p
  di <- consDes <$> hasInfraRelations dk tc
  return $ IntMap.singleton (fromIntegral dk) di
