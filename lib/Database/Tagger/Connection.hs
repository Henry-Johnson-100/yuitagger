{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}

{- |
Module      : Database.Tagger.Connection
Description : Module to open, query, and close Tagger database connections.

License     : GPL-3
Maintainer  : monawasensei@gmail.com
-}
module Database.Tagger.Connection (
  -- * Wrapped types
  open,
  open',
  close,
  query,
  queryNamed,
  query_,
  execute,
  execute_,
  executeNamed,
  executeMany,
  lastInsertRowId,
  initializeDatabase,
  teardownDatabase,

  -- * Internal Connection types

  -- | Functions exposing internal Connection representations. Exposed for convenience.
  withBareConnection,
  withConnection,
  withConnectionHandle,

  -- * Database.SQLite.Simple types

  -- | Types exported from Database.SQLite.Simple for use in 'Database.Tagger`
  Simple.Query,
  Simple.ToRow,
  Database.SQLite.Simple.ToField.ToField,
  Simple.FromRow,
  Simple.Only (..),
  Simple.NamedParam (..),
) where

import Control.Monad (unless, when)
import Data.Maybe
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Data.Version
import qualified Database.SQLite.Simple as Simple
import qualified Database.SQLite.Simple.ToField
import qualified Database.SQLite3 as SQLite3
import Database.Tagger.Query.Type
import Database.Tagger.Script (
  SQLiteScript (SQLiteScript),
  schemaDefinition,
  schemaTeardown,
  update0_3_4_0To0_3_4_2,
 )
import Database.Tagger.Type
import Database.Tagger.Type.Prim (BareConnection (..))
import System.IO
import Tagger.Info (taggerVersion)
import Tagger.Util
import Text.ParserCombinators.ReadP (readP_to_S)

{- |
 Open a new 'TaggedConnection` with the database at the given path.

 The connection's label is set to the path and the lastAccessed time and database version
 is updated.

 If the db info table is not found then the database is initialized, if this is undesired,
  use open'

 Most Tagger connections should be made with this function.
-}
open :: FilePath -> IO TaggedConnection
open p = do
  let tagName = T.pack p
  bc <- fmap BareConnection . Simple.open $ p
  dbInfoTableExists <- taggerDBInfoTableExists bc
  activateForeignKeyPragma bc
  let conn = TaggedConnection tagName bc
  unless dbInfoTableExists (initializeDatabase conn)
  updateTaggerDBInfoVersion bc
  updateTaggerDBInfoLastAccessed bc
  return conn

{- |
 Like 'open` but does NOT update the table with lastAccessedDateTime or the table version.

 Also does not attempt to initialize the database if there is no db info table.
-}
open' :: FilePath -> IO TaggedConnection
open' p = do
  let tagName = T.pack p
  bc <- fmap BareConnection . Simple.open $ p
  activateForeignKeyPragma bc
  return $ TaggedConnection tagName bc

{- |
 Closes a TaggedConnection
-}
close :: TaggedConnection -> IO ()
close =
  withBareConnection
    (withConnection Simple.close)

{- |
 Run a query with a 'TaggedConnection`
-}
query ::
  (Simple.ToRow q, Simple.FromRow r) =>
  TaggedConnection ->
  TaggerQuery ->
  q ->
  IO [r]
query tc (TaggerQuery queryStmnt) params =
  withBareConnection (\bc -> bareQuery bc queryStmnt params) tc

{- |
 Run a query with named parameters.
-}
queryNamed ::
  Simple.FromRow r =>
  TaggedConnection ->
  TaggerQuery ->
  [Simple.NamedParam] ->
  IO [r]
queryNamed tc (TaggerQuery queryStmnt) params =
  withBareConnection (\bc -> bareQueryNamed bc queryStmnt params) tc

{- |
 Run a query taking no parameters with a 'TaggedConnection`

 If the tagged connection's connection is 'Nothing` then an error is printed and
 an empty result list is returned.
-}
query_ ::
  Simple.FromRow r =>
  TaggedConnection ->
  TaggerQuery ->
  IO [r]
query_ tc (TaggerQuery queryStmnt) = withBareConnection (`bareQuery_` queryStmnt) tc

{- |
 Execute a statement on a 'TaggedConnection`

 Executions return no results.

 If the tagged connection's connection is 'Nothing` then an error is printed.
-}
execute ::
  Simple.ToRow q =>
  TaggedConnection ->
  TaggerQuery ->
  q ->
  IO ()
execute tc (TaggerQuery queryStmnt) params =
  withBareConnection
    (\bc -> bareExecute bc queryStmnt params)
    tc

{- |
 Execute a statement taking no parameters on a 'TaggedConnection`

 Executions return no results.

 If the tagged connection's connection is 'Nothing` then an error is printed.
-}
execute_ ::
  TaggedConnection ->
  TaggerQuery ->
  IO ()
execute_ tc (TaggerQuery queryStmnt) =
  withBareConnection
    (`bareExecute_` queryStmnt)
    tc

{- |
 Execute a statement with named parameters.
-}
executeNamed :: TaggedConnection -> TaggerQuery -> [Simple.NamedParam] -> IO ()
executeNamed tc (TaggerQuery queryStmnt) params =
  withBareConnection (\c -> bareExecuteNamed c queryStmnt params) tc

{- |
 Execute a statement on a list of parameters.
-}
executeMany :: Simple.ToRow q => TaggedConnection -> TaggerQuery -> [q] -> IO ()
executeMany tc (TaggerQuery queryStmnt) params =
  withBareConnection
    (\bc -> bareExecuteMany bc queryStmnt params)
    tc

{- |
  Gets the ID of the row last inserted into the database.
-}
lastInsertRowId :: RowId r => TaggedConnection -> IO (RecordKey r)
lastInsertRowId = withBareConnection bareLastInsertRowId

{- |
 Run the Tagger schema definition script on the given connection.

 Should ideally not do anything on a database that is already up-to-date with the current
 schema definition, but it would be best to avoid doing that anyways.
-}
initializeDatabase :: TaggedConnection -> IO ()
initializeDatabase tc = do
  initScript <- schemaDefinition
  withBareConnection
    ( withConnection
        ( withConnectionHandle
            (`SQLite3.exec` (\(SQLiteScript s) -> s) initScript)
        )
    )
    tc

{- |
 DROP all tables defined in the schemaDefinition.

 This is really only used for generating and tearing down test databases.
-}
teardownDatabase :: TaggedConnection -> IO ()
teardownDatabase tc = do
  teardownScript <- schemaTeardown
  withBareConnection
    ( withConnection
        ( withConnectionHandle
            (`SQLite3.exec` (\(SQLiteScript s) -> s) teardownScript)
        )
    )
    tc

{- |
 Run an action using a 'TaggedConnection`'s 'BareConnection`
-}
withBareConnection :: (BareConnection -> t) -> TaggedConnection -> t
withBareConnection f (TaggedConnection _ bc) = f bc

{- |
 Run an action using a 'BareConnection`'s Connection.
-}
withConnection :: (Simple.Connection -> t) -> BareConnection -> t
withConnection f = f . _bareConnection

{- |
 Run an action using a Connection's ConnectionHandle.
-}
withConnectionHandle :: (SQLite3.Database -> c) -> Simple.Connection -> c
withConnectionHandle f = f . Simple.connectionHandle

activateForeignKeyPragma :: BareConnection -> IO ()
activateForeignKeyPragma = flip bareExecute_ "PRAGMA foreign_keys = on"

taggerDBInfoTableExists :: BareConnection -> IO Bool
taggerDBInfoTableExists c = do
  r <-
    bareQuery_
      c
      "SELECT COUNT(*) \
      \FROM sqlite_master \
      \WHERE type = 'table' AND name = 'TaggerDBInfo'" ::
      IO [Simple.Only Int]
  return . all ((> 0) . (\(Simple.Only n) -> n)) $ r

updateTaggerDBInfoLastAccessed :: BareConnection -> IO ()
updateTaggerDBInfoLastAccessed bc = do
  dbInfoTableExists <- taggerDBInfoTableExists bc
  when dbInfoTableExists $ do
    currentTime <- getCurrentTime
    withConnection
      ( \c ->
          Simple.execute
            c
            "UPDATE TaggerDBInfo SET lastAccessed = ?"
            [currentTime]
      )
      bc

updateTaggerDBInfoVersion :: BareConnection -> IO ()
updateTaggerDBInfoVersion bc = do
  dbInfoTableExists <- taggerDBInfoTableExists bc
  maybeCurrentVersion <-
    head'
      . mapMaybe (readVersion . (\(Simple.Only x) -> x))
      <$> bareQuery_ bc "SELECT version FROM TaggerDBInfo LIMIT 1"
  patchDatabase maybeCurrentVersion
  when
    (dbInfoTableExists && isJust maybeCurrentVersion)
    ( withConnection
        ( \c ->
            Simple.execute
              c
              "UPDATE TaggerDBInfo SET version = ?"
              [showVersion taggerVersion]
        )
        bc
    )
 where
  readVersion :: String -> Maybe Version
  readVersion = last' . map fst . readP_to_S parseVersion
  patchDatabase :: Maybe Version -> IO ()
  patchDatabase Nothing =
    hPutStrLn stderr "Unable to determine database version, some operations may fail."
  patchDatabase (Just v) =
    if v /= taggerVersion
      then do
        when
          (makeVersion [0, 3, 4, 0] <= v && v < makeVersion [0, 3, 4, 2])
          v0_3_4_0_v_0_3_4_2
      else pure ()
   where
    v0_3_4_0_v_0_3_4_2 =
      runPatch =<< update0_3_4_0To0_3_4_2
    runPatch p =
      withConnection
        ( withConnectionHandle
            (`SQLite3.exec` (\(SQLiteScript s) -> s) p)
        )
        bc

bareQuery ::
  (Simple.ToRow q, Simple.FromRow r) =>
  BareConnection ->
  Simple.Query ->
  q ->
  IO [r]
bareQuery = withConnection Simple.query

bareQueryNamed ::
  (Simple.FromRow r) =>
  BareConnection ->
  Simple.Query ->
  [Simple.NamedParam] ->
  IO [r]
bareQueryNamed = withConnection Simple.queryNamed

bareQuery_ :: Simple.FromRow r => BareConnection -> Simple.Query -> IO [r]
bareQuery_ = withConnection Simple.query_

bareExecute :: Simple.ToRow q => BareConnection -> Simple.Query -> q -> IO ()
bareExecute = withConnection Simple.execute

bareExecute_ :: BareConnection -> Simple.Query -> IO ()
bareExecute_ = withConnection Simple.execute_

bareExecuteNamed :: BareConnection -> Simple.Query -> [Simple.NamedParam] -> IO ()
bareExecuteNamed = withConnection Simple.executeNamed

bareExecuteMany :: Simple.ToRow q => BareConnection -> Simple.Query -> [q] -> IO ()
bareExecuteMany = withConnection Simple.executeMany

bareLastInsertRowId :: RowId r => BareConnection -> IO (RecordKey r)
bareLastInsertRowId =
  withConnection (fmap RecordKey . Simple.lastInsertRowId)