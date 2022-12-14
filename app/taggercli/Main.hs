{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}

import Control.Lens ((^.))
import Control.Monad (void, when, (<=<))
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import qualified Data.Foldable as F
import qualified Data.HashSet as HS
import Data.List (sortOn)
import Data.Monoid (Any (..))
import qualified Data.Text as T
import qualified Data.Text.IO as T.IO
import Data.Version (showVersion)
import Database.Tagger (
  File (filePath),
  HasConnName (connName),
  TaggedConnection,
  open',
 )
import Opt (mainReportAudit, showStats)
import Opt.Data (
  TaggerCommand (TaggerCommand),
  TaggerDBCommand (TaggerDBCommand),
  TaggerEx (..),
  TaggerQueryCommand (TaggerQueryCommand),
 )
import Opt.Parser (taggerExParser)
import Options.Applicative (execParser)
import System.Directory (
  getCurrentDirectory,
  makeAbsolute,
  setCurrentDirectory,
 )
import System.FilePath (makeRelative, takeDirectory)
import System.IO (stderr)
import Tagger.Info (taggerVersion)
import Text.TaggerQL (TaggerQLQuery (TaggerQLQuery), taggerQL)

main :: IO ()
main = do
  p <- execParser taggerExParser
  runTaggerEx p

runTaggerEx :: TaggerEx -> IO ()
runTaggerEx TaggerExVersion = putStrLn . showVersion $ taggerVersion
runTaggerEx
  ( TaggerExDB
      dbPath
      ( TaggerDBCommand
          a
          s
          (TaggerCommand qc)
        )
    ) =
    do
      curDir <- getCurrentDirectory
      let dbDir = takeDirectory dbPath
      setCurrentDirectory dbDir
      conn <- open' dbPath
      void . flip runReaderT conn $ do
        when (getAny a) mainReportAudit
        when (getAny s) showStats
        maybe (pure ()) runQuery qc
      setCurrentDirectory curDir
   where
    runQuery :: TaggerQueryCommand -> ReaderT TaggedConnection IO ()
    runQuery (TaggerQueryCommand q (Any rel)) = do
      tc <- ask
      let (T.unpack -> connPath) = tc ^. connName
      liftIO $ do
        queryResults <- taggerQL (TaggerQLQuery q) tc
        if HS.null queryResults
          then T.IO.hPutStrLn stderr "No Results."
          else
            mapM_
              ( ( T.IO.putStrLn . T.pack
                    <=< if rel
                      then pure
                      else makeAbsolute
                )
                  . makeRelative connPath
                  . T.unpack
                  . filePath
              )
              . sortOn filePath
              . F.toList
              $ queryResults