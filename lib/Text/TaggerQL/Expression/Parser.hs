{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-typed-holes #-}

module Text.TaggerQL.Expression.Parser (
  parseExpr,
  ParseError,

  -- * For Testing

  -- ** Expression Parsers
  expressionParser,
  untaggedConstParser,
  binaryParser,
  tagExpressionParser,

  -- ** SubExpression Parsers
  subExpressionParser,
  subBinaryParser,
  subExpressionSubParser,

  -- ** Term Parsers
  tagTermParser,
  fileTermParser,

  -- ** Misc
  patternParser,
) where

import Data.Char (toLower, toUpper)
import Data.Functor (($>), (<&>))
import Data.Tagger (SetOp (..))
import Data.Text (Text)
import qualified Data.Text as T
import Text.Parsec (
  ParseError,
  Parsec,
  anyChar,
  between,
  chainl1,
  char,
  many1,
  noneOf,
  parse,
  space,
  spaces,
  try,
  (<|>),
 )
import Text.TaggerQL.Expression.AST (
  Expression (..),
  FileTerm (..),
  SubExpression (..),
  TagTerm (..),
 )

type Parser a = Parsec Text () a

parseExpr :: Text -> Either ParseError Expression
parseExpr = parse expressionParser "TaggerQL"

expressionParser :: Parser Expression
expressionParser =
  spaces
    *> ( between
          (char '(')
          (spaces *> char ')')
          expressionParser
          <|> ( try binaryParser
                  <|> try tagExpressionParser
                  <|> try fileTermValueParser
                  <|> try untaggedConstParser
                  <|> tagTermValueParser
              )
       )

untaggedConstParser :: Parser Expression
untaggedConstParser = ichar 'u' *> char '.' $> UntaggedConst

fileTermValueParser :: Parser Expression
fileTermValueParser = FileTermValue <$> fileTermParser

tagTermValueParser :: Parser Expression
tagTermValueParser = TagTermValue <$> tagTermParser

binaryParser :: Parser Expression
binaryParser = chainl1 expressionParser (flip Binary <$> setOpParser)

subExpressionParser :: Parser SubExpression
subExpressionParser =
  spaces
    *> ( between
          (char '(')
          (spaces *> char ')')
          subExpressionParser
          <|> ( try subBinaryParser
                  <|> try subExpressionSubParser
                  <|> subTagParser
              )
       )

subTagParser :: Parser SubExpression
subTagParser = SubTag <$> tagTermParser

subBinaryParser :: Parser SubExpression
subBinaryParser = chainl1 subExpressionParser (flip SubBinary <$> setOpParser)

subExpressionSubParser :: Parser SubExpression
subExpressionSubParser =
  SubExpression <$> tagTermParser
    <*> ( spaces
            *> between
              (char '{')
              (spaces *> char '}')
              subExpressionParser
        )

tagExpressionParser :: Parser Expression
tagExpressionParser =
  TagExpression <$> tagTermParser
    <*> ( spaces
            *> between
              (char '{')
              (spaces *> char '}')
              subExpressionParser
        )

fileTermParser :: Parser FileTerm
fileTermParser = ichar 'p' *> char '.' *> patternParser <&> FileTerm

tagTermParser :: Parser TagTerm
tagTermParser =
  ( ( try (ichar 'r' *> char '.' $> MetaDescriptorTerm)
        <|> (ichar 'd' *> char '.' $> DescriptorTerm)
    )
      <|> pure MetaDescriptorTerm
  )
    <*> patternParser

patternParser :: Parser Text
patternParser =
  T.pack <$> many1 ((char '\\' *> anyChar) <|> notRestricted)

notRestricted :: Parser Char
notRestricted = noneOf restrictedChars

setOpParser :: Parser SetOp
setOpParser =
  try (spaces *> explicitSetOpParser)
    <|> (space $> Intersect)

explicitSetOpParser :: Parser SetOp
explicitSetOpParser = unionParser <|> intersectParser <|> differenceParser
 where
  unionParser = char '|' $> Union
  intersectParser = char '&' $> Intersect
  differenceParser = char '!' $> Difference

ichar :: Char -> Parser Char
ichar c = char (toUpper c) <|> char (toLower c)

restrictedChars :: [Char]
restrictedChars = "(){}!&|.\r\n"