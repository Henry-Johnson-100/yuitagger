{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use const" #-}

module Text.TaggerQL.Expression.Engine (
  runExpr,
  evalExpr,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import Data.HashSet (HashSet)
import qualified Data.HashSet as HS
import Data.Hashable (Hashable)
import Data.Tagger (SetOp (..))
import Database.Tagger.Connection (query)
import Database.Tagger.Query (
  flatQueryForFileByTagDescriptorPattern,
  flatQueryForFileOnMetaRelationPattern,
  queryForFileByPattern,
  queryForUntaggedFiles,
 )
import Database.Tagger.Type (
  File,
  Tag (tagId, tagSubtagOfId),
  TaggedConnection,
 )
import Text.RawString.QQ (r)
import Text.TaggerQL.Expression.AST (
  Expression (..),
  FileTerm (FileTerm),
  SubExpression (..),
  TagTerm (..),
 )

{- |
 Query an 'Expression`

 thin wrapper for 'evalExpr`
-}
runExpr :: Expression -> TaggedConnection -> IO (HashSet File)
runExpr expr = runReaderT (evalExpr expr)

evalExpr :: Expression -> ReaderT TaggedConnection IO (HashSet File)
evalExpr expr = case expr of
  UntaggedConst -> ask >>= liftIO . fmap HS.fromList . queryForUntaggedFiles
  FileTermValue (FileTerm txt) ->
    ask >>= liftIO . fmap HS.fromList . queryForFileByPattern txt
  TagTermValue tt ->
    ask
      >>= liftIO . fmap HS.fromList . case tt of
        DescriptorTerm txt -> flatQueryForFileByTagDescriptorPattern txt
        MetaDescriptorTerm txt -> flatQueryForFileOnMetaRelationPattern txt
  TagExpression tt subExpr -> do
    supertags <- ask >>= liftIO . fmap HS.fromList . queryTags tt
    subExprResult <- runReaderT (evalSubExpression subExpr) supertags
    ask >>= liftIO . toFileSet subExprResult
  Binary ex so ex' -> do
    lhs <- evalExpr ex
    rhs <- evalExpr ex'
    return $ dispatchComb so lhs rhs

evalSubExpression ::
  SubExpression ->
  ReaderT
    (HashSet Tag)
    (ReaderT TaggedConnection IO)
    (HashSet Tag)
evalSubExpression subExpr = case subExpr of
  SubTag tt -> do
    subtags <-
      lift ask
        >>= liftIO
          . fmap (HS.fromList . map tagSubtagOfId)
          . queryTags tt
    joinSubtags subtags
  SubBinary se so se' -> do
    let binaryCond x y = case so of
          Union -> x || y
          Intersect -> x && y
          Difference -> x && not y
    lhs <- HS.map tagSubtagOfId <$> evalSubExpression se
    rhs <- HS.map tagSubtagOfId <$> evalSubExpression se'
    fmap
      ( HS.filter
          ( \supertag ->
              HS.member (Just . tagId $ supertag) lhs
                `binaryCond` HS.member (Just . tagId $ supertag) rhs
          )
      )
      ask
  SubExpression tt se -> do
    nextSupertags <- lift ask >>= liftIO . fmap HS.fromList . queryTags tt
    nestedSubExprResult <-
      HS.map tagSubtagOfId
        <$> lift (runReaderT (evalSubExpression se) nextSupertags)
    joinSubtags nestedSubExprResult
 where
  -- Filter the given set of tags based on whether or not it appears in the latter given
  -- set of subTagOfIds.
  joinSubtags subtags =
    fmap (HS.filter (\(Just . tagId -> supertagId) -> HS.member supertagId subtags)) ask

dispatchComb :: Hashable a => SetOp -> HashSet a -> HashSet a -> HashSet a
dispatchComb so =
  case so of
    Union -> HS.union
    Intersect -> HS.intersection
    Difference -> HS.difference

toFileSet :: HashSet Tag -> TaggedConnection -> IO (HashSet File)
toFileSet (map tagId . HS.toList -> ts) conn = do
  results <- mapM (query conn q . (: [])) ts
  return . HS.unions . map HS.fromList $ results
 where
  q =
    [r|
SELECT
  f.id
  ,f.filePath
FROM File f
JOIN Tag t ON f.id = t.fileId
WHERE t.id = ?
    |]

queryTags :: TagTerm -> TaggedConnection -> IO [Tag]
queryTags tt c =
  case tt of
    DescriptorTerm txt -> query c tagQueryOnDescriptorPattern [txt]
    MetaDescriptorTerm txt -> query c tagQueryOnMetaDescriptorPattern [txt]
 where
  tagQueryOnDescriptorPattern =
    [r|
      SELECT
        t.id,
        t.fileId,
        t.descriptorId,
        t.subTagOfId
      FROM Tag t
      JOIN Descriptor d ON t.descriptorId = d.id
      WHERE d.descriptor LIKE ? ESCAPE '\'
      |]
  tagQueryOnMetaDescriptorPattern =
    [r|
      SELECT
        t.id
        ,t.fileId
        ,t.descriptorId
        ,t.subTagOfId
      FROM Tag t
      JOIN (
        WITH RECURSIVE r(id) AS (
          SELECT id
          FROM Descriptor
          WHERE descriptor LIKE ? ESCAPE '\'
          UNION
          SELECT infraDescriptorId
          FROM MetaDescriptor md
          JOIN r ON md.metaDescriptorId = r.id
        )
        SELECT id FROM r
      ) AS d ON t.descriptorId = d.id|]
