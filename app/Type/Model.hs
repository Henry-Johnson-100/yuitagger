{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TemplateHaskell #-}

module Type.Model
  ( module Type.Model.Prim,
    fileSelection,
    fileSingle,
    descriptorDb,
    descriptorTree,
    connectionString,
    fileSetArithmetic,
    queryCriteria,
    fileSelectionQuery,
    doSoloTag,
    shellCmd,
    HasFileSingle,
    HasDoSoloTag,
    HasFileSetArithmetic,
    HasDescriptorTree,
    HasQueryCriteria,
    HasFileSelectionQuery,
    HasShellCmd,
  )
where

import Control.Lens (abbreviatedFields, makeLensesWith)
import Type.Model.Prim

makeLensesWith abbreviatedFields ''TaggerModel