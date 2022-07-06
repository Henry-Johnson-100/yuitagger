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
import Control.Monad.Trans.Maybe
import Data.Config
import Data.Event
import qualified Data.Foldable as F
import qualified Data.HashSet as HS
import Data.HierarchyMap (empty)
import qualified Data.IntMap.Strict as IntMap
import Data.Model
import Data.Model.Shared
import qualified Data.OccurrenceHashMap as OHM
import Data.Sequence (Seq ((:<|), (:|>)))
import qualified Data.Sequence as Seq
import Data.Tagger
import Data.Text (Text)
import qualified Data.Text as T
import Database.Tagger
import Monomer
import Paths_tagger
import System.FilePath
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
      TaggerInit -> [Event (DoDescriptorTreeEvent DescriptorTreeInit)]
      RefreshUI ->
        [ Event (DoDescriptorTreeEvent RefreshBothDescriptorTrees)
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]
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
          (f :<| fs) ->
            [ Event . DoFocusedFileEvent . PutFile $ f
            , Model $ model & fileSelectionModel . selection .~ (fs |> f)
            ]
      CyclePrevFile ->
        case model ^. fileSelectionModel . selection of
          Seq.Empty -> []
          (fs :|> f) ->
            [ Event . DoFocusedFileEvent . PutFile $ f
            , Model $ model & fileSelectionModel . selection .~ (f <| fs)
            ]
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
            newSeq = Seq.fromList . HS.toList . combFun currentSet $ fs
         in [ Model $ model & fileSelectionModel . selection .~ newSeq
            , Event
                ( DoFileSelectionEvent
                    (RefreshTagOccurrencesWith (fmap fileId newSeq))
                )
            , Event (DoFileSelectionEvent . MakeFileSelectionInfoMap $ newSeq)
            ]
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
        , Event (ClearTextField (TaggerLens (fileSelectionModel . queryText)))
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
      RefreshTagOccurrencesWith fks ->
        [ Task
            ( DoFileSelectionEvent . PutTagOccurrenceHashMap_
                <$> getTagOccurrencesByFileKey fks conn
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
        , Event (ClearTextField (TaggerLens $ focusedFileModel . tagText))
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]
      DeleteTag t ->
        [ Task (IOEvent <$> deleteTags [t] conn)
        , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
        ]
      MoveTag
        (ConcreteTag oldTagKey (Descriptor dk _) _)
        newMaybeSubTagKey ->
          let (File fk _) =
                concreteTaggedFile $
                  model
                    ^. focusedFileModel . focusedFile
           in [ Task
                  ( IOEvent
                      <$> do
                        unless (fk == focusedFileDefaultRecordKey) $ do
                          newTags <- insertTags [(fk, dk, newMaybeSubTagKey)] conn
                          -- moving all old subtags to the new tag
                          -- or else they will be cascade deleted when the old tag is.
                          moveSubTags ((oldTagKey,) <$> newTags) conn
                          deleteTags [oldTagKey] conn
                  )
              , Event . DoFocusedFileEvent $ RefreshFocusedFileAndSelection
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
                    <$> unless
                      (fk == focusedFileDefaultRecordKey)
                      (void (insertTags [(fk, dk, mtk)] conn))
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
                ( RequestFocusedNode $
                    model
                      ^. conf
                        . descriptorTreeConf
                        . treeRootRequest
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
              then [Task (IOEvent <$> putStrLn "null text")]
              else
                [ Task
                    ( IOEvent
                        <$> updateDescriptors [(updateText, rkd)] conn
                    )
                , Event (DoDescriptorTreeEvent RefreshBothDescriptorTrees)
                ]

toDescriptorInfo :: TaggedConnection -> Descriptor -> IO (IntMap.IntMap DescriptorInfo)
toDescriptorInfo tc (Descriptor dk p) = do
  let consDes b = DescriptorInfo b p
  di <- consDes <$> hasInfraRelations dk tc
  return $ IntMap.singleton (fromIntegral dk) di
