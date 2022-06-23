{-# LANGUAGE OverloadedStrings #-}

module Test.Text.TaggerQL.Parser (
    queryParserTests,
) where

import Data.Char
import Data.Tagger
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit
import Text.Parsec
import Text.TaggerQL.AST
import Text.TaggerQL.Parser.Internal

queryParserTests :: TestTree
queryParserTests =
    testGroup
        "QueryParser Tests"
        []

--     testCase
--     "escaped_bracket_sequence_as_term"
--     ( assertEqual
--         "escaped subclause brackets are a valid term"
--         (Right . TaggerQLSimpleToken . TaggerQLSimpleTerm DescriptorCriteria $ "u[]")
--         (parse taggerQLTokenParser "test" "u\\[\\]")
--     )
-- , testCase
--     "escaped_bracket_sequence"
--     ( assertEqual
--         "Escaped bracket sequences should be valid terms"
--         ( Right
--             [ TaggerQLSimpleToken $
--                 TaggerQLSimpleTerm MetaDescriptorCriteria "r.test"
--             , TaggerQLSimpleToken $
--                 TaggerQLSimpleTerm DescriptorCriteria "u[]"
--             ]
--         )
--         (parse (sepBy taggerQLTokenParser spaces) "test" "r.test u\\[\\]")
--     )
-- , testCase
--     "escaped_bracket_term_with_subclause"
--     ( assertEqual
--         "Can use escaped bracket terms and subclauses"
--         ( Right $
--             TaggerQLComplexToken
--               ( TaggerQLComplexTerm
--                   DescriptorCriteria
--                   "u[]"
--                   ( TaggerQLSubClause
--                       Union
--                       [ TaggerQLSimpleToken
--                           . TaggerQLSimpleTerm DescriptorCriteria
--                           $ "test"
--                       ]
--                   )
--               )
--         )
--         (parse taggerQLTokenParser "test" "u\\[\\] u[test]")
--     )
-- , let charSet = [id, toUpper] <*> "abcdefghijklmnopqrstuvwxyz1234567890"
--    in testCase
--         "single_chars_are_valid_terms"
--         ( assertEqual
--             "semi-special single chars should not have to be escaped to be valid terms."
--             ( Right
--                 . TaggerQLSimpleToken
--                 . TaggerQLSimpleTerm DescriptorCriteria
--                 <$> (T.singleton <$> charSet)
--             )
--             (parse taggerQLTokenParser "test" <$> (T.singleton <$> charSet))
--         )
-- , testCase
--     "terms_starting_with_semi_special_chars_are_valid"
--     ( assertEqual
--         "Terms are allowed to start with semi special chars like 'u'"
--         (Right . TaggerQLSimpleToken . TaggerQLSimpleTerm DescriptorCriteria $ "unrelated")
--         (parse taggerQLTokenParser "test" "unrelated")
--     )