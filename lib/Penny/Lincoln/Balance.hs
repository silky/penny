module Penny.Lincoln.Balance (
    Balance
  , unBalance
  , Balanced(Balanced, Inferable, NotInferable)
  , balanced
  , isInferable
  , entryToBalance
  , entriesToBalanced
  , removeZeroCommodities
  , BottomLine(Zero, NonZero)
  , Column(Column, colDrCr, colQty)
  ) where

import Data.Map ( Map )
import qualified Data.Map as M
import Data.Monoid ( Monoid, mempty, mappend, mconcat )

import Penny.Lincoln.Bits (
  add, difference, Difference(LeftBiggerBy, RightBiggerBy, Equal))
import qualified Penny.Lincoln.Bits as B

-- | A balance summarizes several entries. You do not create a Balance
-- directly. Instead, use 'entryToBalance'.
newtype Balance = Balance (Map B.Commodity BottomLine)
                  deriving (Show, Eq)

-- | Returns a map where the keys are the commodities in the balance
-- and the values are the balance for each commodity. If there is no
-- balance at all, this map can be empty.
unBalance :: Balance -> Map B.Commodity BottomLine
unBalance (Balance m) = m

-- | Returned by 'balanced'.
data Balanced = Balanced
              | Inferable (B.Entry B.Qty)
              | NotInferable
              deriving (Show, Eq)

-- | Computes whether a Balance map is Balanced.
--
-- > balanced mempty == Balanced
balanced :: Balance -> Balanced
balanced (Balance m) = M.foldrWithKey f Balanced m where
  f c n b = case n of
    Zero -> b
    (NonZero col) -> case b of
      Balanced -> let
        dc = case colDrCr col of
          B.Debit -> B.Credit
          B.Credit -> B.Debit
        q = colQty col
        in Inferable (B.Entry dc (B.Amount q c))
      _ -> NotInferable

isInferable :: Balanced -> Bool
isInferable (Inferable _) = True
isInferable _ = False

-- | Converts an Entry to a Balance.
entryToBalance :: B.HasQty q => B.Entry q -> Balance
entryToBalance (B.Entry dc am) = Balance $ M.singleton c no where
  c = B.commodity am
  no = NonZero (Column dc (B.toQty . B.qty $ am))

-- | Converts multiple Entries to a Balanced.
entriesToBalanced :: B.HasQty q => [B.Entry q] -> Balanced
entriesToBalanced
  = balanced
  . mconcat
  . map entryToBalance

data BottomLine = Zero
            | NonZero Column
            deriving (Show, Eq)

instance Monoid BottomLine where
  mempty = Zero
  mappend n1 n2 = case (n1, n2) of
    (Zero, Zero) -> Zero
    (Zero, (NonZero c)) -> NonZero c
    ((NonZero c), Zero) -> NonZero c
    ((NonZero c1), (NonZero c2)) ->
      let (Column dc1 q1) = c1
          (Column dc2 q2) = c2
      in if dc1 == dc2
         then NonZero $ Column dc1 (q1 `add` q2)
         else case difference q1 q2 of
           LeftBiggerBy diff ->
             NonZero $ Column dc1 diff
           RightBiggerBy diff ->
             NonZero $ Column dc2 diff
           Equal -> Zero

data Column = Column { colDrCr :: B.DrCr
                     , colQty :: B.Qty }
              deriving (Show, Eq)


-- | Add two Balances together. Commodities are never removed from the
-- balance, even if their balance is zero. Instead, they are left in
-- the balance. Sometimes you want to know that a commodity was in the
-- account but its balance is now zero.
instance Monoid Balance where
  mempty = Balance M.empty
  mappend (Balance t1) (Balance t2) =
    Balance $ M.unionWith mappend t1 t2


-- | Removes zero balances from a Balance.
removeZeroCommodities :: Balance -> Balance
removeZeroCommodities (Balance m) =
  let p b = case b of
        Zero -> False
        _ -> True
      m' = M.filter p m
  in Balance m'
