-- | Default options for the Convert report when used from the command
-- line.
module Penny.Cabin.Balance.Convert.Options where

import qualified Penny.Cabin.Balance.Convert.Parser as P
import qualified Penny.Cabin.Parsers as CP
import qualified Penny.Cabin.Options as CO
import qualified Penny.Shield as S

-- | Default options for the Convert report. This record is used as
-- the starting point when parsing in options from the command
-- line. You don't need to use it if you are setting the options for
-- the Convert report directly from your own code.

data DefaultOpts = DefaultOpts
  { showZeroBalances :: CO.ShowZeroBalances
  , target :: P.Target
  , sortOrder :: CP.SortOrder
  , sortBy :: P.SortBy
  }

toParserOpts :: DefaultOpts -> S.Runtime -> P.Opts
toParserOpts d rt = P.Opts
  { P.showZeroBalances = showZeroBalances d
  , P.target = target d
  , P.dateTime = S.currentTime rt
  , P.sortOrder = sortOrder d
  , P.sortBy = sortBy d
  , P.percentRpt = Nothing
  }

defaultOptions :: DefaultOpts
defaultOptions = DefaultOpts
  { showZeroBalances = CO.ShowZeroBalances False
  , target = P.AutoTarget
  , sortOrder = CP.Ascending
  , sortBy = P.SortByName
  }


