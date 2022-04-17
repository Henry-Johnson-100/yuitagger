{-# HLINT ignore "Redundant return" #-}
{-# HLINT ignore "Use <&>" #-}
{-# HLINT ignore "Redundant flip" #-}
{-# HLINT ignore "Redundant $" #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

module Main where

import Control.Lens ((^.))
import Control.Monad.Trans.Except (runExceptT)
import qualified Data.Text as T
import Database.SQLite.Simple (Connection, close, open)
import Database.Tagger.Access (activateForeignKeyPragma)
import Event.Handler (taggerEventHandler)
import IO
import Monomer
import Node.Application
import Type.Config
import Type.Model

taggerApplicationUI ::
  WidgetEnv TaggerModel TaggerEvent ->
  TaggerModel ->
  WidgetNode TaggerModel TaggerEvent
taggerApplicationUI wenv model' = widgetTree
  where
    widgetTree =
      let !model = model'
       in vstack
            [ menubar,
              zstack
                [ visibility model Configure configureZone,
                  visibility model Main
                    . vgrid
                    $ [ box_ [alignMiddle] . fileSinglePreviewWidget $ model,
                        hgrid
                          [ vstack
                              [ queryAndTagEntryWidget,
                                descriptorTreeQuadrantWidget
                                  (model ^. descriptorTree)
                                  (model ^. unrelatedDescriptorTree)
                              ],
                            fileSelectionWidget (model ^. fileSelection)
                          ]
                      ]
                ]
            ]

taggerApplicationConfig :: [AppConfig TaggerEvent]
taggerApplicationConfig =
  appInitEvent TaggerInit : themeConfig

runTaggerWindow :: TaggerConfig -> IO ()
runTaggerWindow cfg =
  startApp
    (emptyTaggerModel cfg)
    taggerEventHandler
    taggerApplicationUI
    taggerApplicationConfig

getTaggedConnection :: FilePath -> IO TaggedConnection
getTaggedConnection p = do
  dbConn <- open p
  return (TaggedConnection (T.pack p) (Just dbConn))

closeTaggedConnection :: TaggedConnection -> IO ()
closeTaggedConnection (TaggedConnection _ mc) = maybe (pure ()) close mc

main :: IO ()
main = do
  configPath <- getConfigPath
  try' (getConfig configPath) $
    \config -> do
      runTaggerWindow config
  where
    try' e c = runExceptT e >>= either (hPutStrLn stderr) c
