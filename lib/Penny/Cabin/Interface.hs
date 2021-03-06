-- | An interface for other Penny components to use. A report is
-- anything that is a 'Report'.
module Penny.Cabin.Interface where

import qualified Data.Prednote.Expressions as Exp
import qualified Penny.Cabin.Scheme as S
import qualified Data.Prednote as Pd
import qualified Data.Text as X
import Text.Matchers (CaseSensitive)
import qualified System.Console.MultiArg as MA
import qualified System.Console.Rainbow as R

import qualified Penny.Lincoln as L
import qualified Penny.Liberty as Ly
import Penny.Shield (Runtime)

-- | The function that will print the report, and the positional
-- arguments. If there was a problem parsing the command line options,
-- return an Exception with an error message.

-- | Parsing the filter options can have one of two results: a help
-- string, or a list of positional arguments and a function that
-- prints a report. Or, the parse might fail.

type PosArg = String
type HelpStr = String
type ArgsAndReport = ([PosArg], PrintReport)

-- | The result of parsing the arguments to a report. Failures are
-- indicated with a Text. The name of the executable and the word
-- @error@ will be prepended to this Text; otherwise, it is printed
-- as-is, so be sure to include any trailing newline if needed.
type ParseResult = Either X.Text ArgsAndReport

type PrintReport
  = (L.Amount L.Qty -> X.Text)
  -- ^ Function that gives a rendering for quantities that are not
  -- already formatted.  This function is passed as part of
  -- PrintReport because it allows the function to be built after the
  -- ledger has already been parsed.

  -> [L.Transaction]
  -- ^ All transactions to be included in the report. The report must
  -- sort and filter them

  -> [L.PricePoint]
  -- ^ PricePoints to be included in the report


  -> Either X.Text [R.Chunk]
  -- ^ The exception type is a strict Text, containing the error
  -- message. The success type is a list of either a Chunk or a PreChunk
  -- containing the resulting report. This allows for errors after the
  -- list of transactions has been seen. The name of the executable and
  -- the word @error@ will be prepended to this Text; otherwise, it is
  -- printed as-is, so be sure to include any trailing newline if
  -- needed.


type Report = Runtime -> (HelpStr, MkReport)
type MkReport
  = CaseSensitive
  -- ^ Result from previous parses indicating whether the user desires
  -- case sensitivity (this may have been changed in the filtering
  -- options)

  -> (CaseSensitive -> X.Text -> Either X.Text (Pd.Predbox X.Text))
  -- ^ Result from previous parsers indicating the matcher factory the
  -- user wishes to use

  -> S.Changers
  -- ^ Result from previous parsers indicating which color scheme to
  -- use.

  -> Exp.ExprDesc
  -- ^ Result from previous parsers indicating whether the user wants
  -- RPN or infix

  -> ([L.Transaction] -> [(Ly.LibertyMeta, L.Posting)])
  -- ^ Result from previous parsers that will sort and filter incoming
  -- transactions

  -> MA.Mode (MA.ProgName -> String) ParseResult
