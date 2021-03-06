{-# LANGUAGE RankNTypes #-}
module Penny.Cabin.Posts.Meta
  ( M.VisibleNum(M.unVisibleNum)
  , PostMeta(filteredNum, sortedNum, visibleNum, balance)
  , toBoxList
  ) where

import Data.List (mapAccumL)
import qualified Penny.Lincoln as L
import qualified Penny.Lincoln.Queries as Q
import qualified Penny.Liberty as Ly
import qualified Penny.Cabin.Meta as M
import qualified Penny.Cabin.Options as CO
import qualified Data.Prednote as Pe
import Data.Monoid (mempty, mappend)

data PostMeta = PostMeta
  { filteredNum :: Ly.FilteredNum
  , sortedNum :: Ly.SortedNum
  , visibleNum :: M.VisibleNum
  , balance :: L.Balance }
  deriving Show


addMetadata
  :: [(L.Balance, (Ly.LibertyMeta, L.Posting))]
  -> [(PostMeta, L.Posting)]
addMetadata = L.serialItems f where
  f ser (bal, (lm, p)) = (pm, p)
    where
      pm = PostMeta
        { filteredNum = Ly.filteredNum lm
        , sortedNum = Ly.sortedNum lm
        , visibleNum = M.VisibleNum ser
        , balance = bal
        }

-- | Adds appropriate metadata, including the running balance, to a
-- list of Box. Because all posts are incorporated into the running
-- balance, first calculates the running balance for all posts. Then,
-- removes posts we're not interested in by applying the predicate and
-- the post-filter. Finally, adds on the metadata, which will include
-- the VisibleNum.
toBoxList
  :: CO.ShowZeroBalances
  -> Pe.Predbox (Ly.LibertyMeta, L.Posting)
  -- ^ Removes posts from the report if applying this function to the
  -- post returns a value other than Just True. Posts removed still
  -- affect the running balance.

  -> [Ly.PostFilterFn]
  -- ^ Applies these post-filters to the list of posts that results
  -- from applying the predicate above. Might remove more
  -- postings. Postings removed still affect the running balance.

  -> [(Ly.LibertyMeta, L.Posting)]
  -> [(PostMeta, L.Posting)]
toBoxList szb pdct pff
  = addMetadata
  . Ly.processPostFilters pff
  . filter (Pe.rBool . Pe.evaluate pdct . snd)
  . addBalances szb

addBalances
  :: CO.ShowZeroBalances
  -> [(a, L.Posting)]
  -> [(L.Balance, (a, L.Posting))]
addBalances szb = snd . mapAccumL (balanceAccum szb) mempty

balanceAccum
  :: CO.ShowZeroBalances
  -> L.Balance
  -> (a, L.Posting)
  -> (L.Balance, (L.Balance, (a, L.Posting)))
balanceAccum (CO.ShowZeroBalances szb) balOld (x, po) =
  let balThis = either L.entryToBalance L.entryToBalance
                . Q.entry $ po
      balNew = mappend balOld balThis
      balNoZeroes = L.removeZeroCommodities balNew
      bal' = if szb then balNew else balNoZeroes
      po' = (bal', (x, po))
  in (bal', po')

