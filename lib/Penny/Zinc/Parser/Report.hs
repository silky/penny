module Penny.Zinc.Parser.Report (report) where

import System.Console.MultiArg.Prim (Parser)
import qualified System.Console.MultiArg.Combinator as C

import qualified Penny.Cabin.Interface as I
import qualified Penny.Shield as S
import qualified Data.Set as Set

-- | Given a Runtime and a list of available Reports, returns a Parser
-- that will return a function corresponding to the report the user
-- desires. The parser returned assumes that the filtering options
-- have already been parsed. The returned parser parses all options
-- corresponding to report options in order to return the function.
report ::
  S.Runtime
  -- ^ Things only known at runtime, such as the current date
  
  -> [I.Report]
  -- ^ List of available Reports

  -> Parser I.ParserFunc
report rt rs = do
  let toPair r = (I.name r, I.parseReport r rt)
      alist = map toPair rs
      set = Set.fromList . map fst $ alist
  (_, n) <- C.matchApproxWord set
  case lookup n alist of
    Nothing -> error $ "Penny.Zinc.Parser.Report: error: "
               ++ "report not found"
    Just rptFunc -> rptFunc



