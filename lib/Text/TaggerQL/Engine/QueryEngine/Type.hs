{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StrictData #-}
{-# OPTIONS_HADDOCK hide #-}

module Text.TaggerQL.Engine.QueryEngine.Type (
  QueryEnv (..),
  QueryReaderT,
  QueryReader,
  TagKeySet,
  TaggedConnection,
  module Control.Monad.Trans.Reader,
  lift,
) where

import Control.Monad.Trans.Class (MonadTrans (lift))
import Control.Monad.Trans.Reader
import Data.Functor.Identity (Identity)
import Data.IntSet (IntSet)
import Data.String (IsString)
import Database.Tagger (TaggedConnection)
import Database.Tagger.Query.Type (TaggerQuery)

data QueryEnv a = QueryEnv
  { queryEnvConn :: TaggedConnection
  , queryEnv :: a
  }
  deriving (Show, Eq, Functor)

type QueryReaderT a m b = ReaderT (QueryEnv a) m b

type QueryReader a b = QueryReaderT a Identity b

type TagKeySet = IntSet
