module Database.TaggerNew.Type
  ( File (..),
    Descriptor (..),
    Tag (..),
    MetaDescriptor (..),
    DescriptorTree (..),
    insertIntoDescriptorTree,
    descriptorTreeElem,
    flattenTree,
    descriptorTreeChildren,
    dbFile,
    getNode,
  )
where

import qualified Control.Monad
import qualified Control.Monad.Trans.Class as Trans
import Control.Monad.Trans.Maybe (MaybeT (MaybeT))
import qualified Data.List
import qualified Data.Text
import qualified System.Directory as SysDir

data File = File {fileId :: Int, filePath :: Data.Text.Text} deriving (Show, Eq)

instance Ord File where
  compare (File _ px) (File _ py) = compare px py

data Descriptor = Descriptor {descriptorId :: Int, descriptor :: Data.Text.Text}
  deriving (Show, Eq)

instance Ord Descriptor where
  compare (Descriptor _ dx) (Descriptor _ dy) = compare dx dy

data Tag = Tag {fileTagId :: Int, descriptorTagId :: Int} deriving (Show, Eq, Ord)

data MetaDescriptor = MetaDescriptor
  { metaDescriptorId :: Int,
    infraDescriptorId :: Int
  }
  deriving (Show, Eq)

data FileWithTags = FileWithTags {file :: File, tags :: [Descriptor]}

instance Eq FileWithTags where
  (FileWithTags fx _) == (FileWithTags fy _) = fx == fy

instance Show FileWithTags where
  show =
    Control.Monad.liftM2
      (++)
      (flip (++) " : " . show . file)
      (concatMap show . Data.List.sort . tags)

data DescriptorTree
  = Infra Descriptor
  | Meta Descriptor [DescriptorTree]
  | NullTree
  deriving (Show, Eq)

insertIntoDescriptorTree :: DescriptorTree -> DescriptorTree -> DescriptorTree
insertIntoDescriptorTree mt it =
  case mt of
    Infra md -> Meta md [it]
    Meta md cs -> Meta md (it : cs)
    NullTree -> it

descriptorTreeChildren :: DescriptorTree -> [DescriptorTree]
descriptorTreeChildren tr =
  case tr of
    Infra mk -> []
    Meta mk cs -> cs
    NullTree -> []

descriptorTreeElem :: Descriptor -> DescriptorTree -> Bool
descriptorTreeElem k mt =
  case mt of
    Infra mk -> k == mk
    Meta mk cs ->
      (k == mk) || any (descriptorTreeElem k) cs
    NullTree -> False

getNode :: DescriptorTree -> Maybe Descriptor
getNode tr =
  case tr of
    NullTree -> Nothing
    Infra d -> Just d
    Meta d _ -> Just d

flattenTree :: DescriptorTree -> [Descriptor]
flattenTree = flattenTree' []
  where
    flattenTree' :: [Descriptor] -> DescriptorTree -> [Descriptor]
    flattenTree' xs tr =
      case tr of
        Infra d -> d : xs
        Meta d cs -> Data.List.foldl' flattenTree' (d : xs) cs
        NullTree -> []

-- | A system safe constructor for a File from a string.
-- If the file exists, returns it with its absolute path.
-- Resolves symbolic links
dbFile :: File -> MaybeT IO File
dbFile rawFile = do
  existsFile <- fileExists rawFile
  resolve existsFile
  where
    fileExists :: File -> MaybeT IO File
    fileExists f' = do
      exists <- Trans.lift . SysDir.doesFileExist . Data.Text.unpack . filePath $ f'
      if exists then return f' else (MaybeT . pure) Nothing
    resolve :: File -> MaybeT IO File
    resolve (File fid fp') = do
      let fp = Data.Text.unpack fp'
      isSymlink <- Trans.lift . SysDir.pathIsSymbolicLink $ fp
      resolved <-
        if isSymlink then (Trans.lift . SysDir.getSymbolicLinkTarget) fp else return fp
      absPath <- Trans.lift . SysDir.makeAbsolute $ resolved
      return . File fid . Data.Text.pack $ absPath