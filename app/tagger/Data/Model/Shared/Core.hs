{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use newtype instead of data" #-}
module Data.Model.Shared.Core (
  Visibility (..),
  toggleAltVis,
  setPaneVis,
  unsetPaneVis,
  hasVis,
) where

import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)

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
  | VisibilityPanes Visibility (Set Visibility)
  deriving (Show, Eq, Ord)

setPaneVis :: Visibility -> Visibility -> Visibility
setPaneVis x y =
  case x of
    VisibilityPanes x' s -> VisibilityPanes x' (S.insert y s)
    _ -> VisibilityPanes x (S.singleton y)

unsetPaneVis :: Visibility -> Visibility -> Visibility
unsetPaneVis x y =
  case x of
    VisibilityPanes x' s ->
      let newVisSet = S.delete y s
       in if S.null newVisSet then x' else VisibilityPanes x' newVisSet
    _ -> x

hasVis :: Visibility -> Visibility -> Bool
hasVis x y =
  case x of
    VisibilityPanes x' s -> x' == y || S.member y s
    _ -> x == y

{- |
 Switches between Main and Alt visibility.

 Does nothing if the visibility is not either of these two constructors.
-}
toggleAltVis :: Visibility -> Visibility
toggleAltVis VisibilityAlt = VisibilityMain
toggleAltVis VisibilityMain = VisibilityAlt
toggleAltVis x = x