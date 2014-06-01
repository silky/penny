module Penny.Lincoln.Concrete
  ( Concrete
  , unConcrete
  , HasConcrete(..)
  , compute
  , add
  , subt
  , mult
  , negate
  ) where

import qualified Penny.Lincoln.Rep as A
import qualified Deka.Native.Abstract as DN
import qualified Penny.Lincoln.Native as N
import qualified Deka.Dec as D
import Penny.Lincoln.Lane
import Prelude hiding (negate)

newtype Concrete = Concrete { unConcrete :: D.Dec }
  deriving Show

instance Laned Concrete where
  lane (Concrete d)
    | D.isZero d = Center
    | D.isPositive d = NonCenter Debit
    | otherwise = NonCenter Credit

class HasConcrete a where
  concrete :: a -> Concrete

instance HasConcrete Concrete where
  concrete = id

instance HasConcrete D.Dec where
  concrete a
    | finite = Concrete a
    | otherwise = error "decToConcrete: not a normal number"
    where
      finite = compute . D.isNormal $ a

compute :: D.Ctx a -> a
compute c
  | fl == D.emptyFlags = r
  | otherwise = error
        "Penny.Lincoln.Concrete: computation out of range"
  where
    (r, fl) = D.runCtxStatus c

instance HasConcrete (A.Rep a) where
  concrete r = Concrete d
    where
      (dec, fl) = DN.abstractToDec abstract
      abstract = DN.Abstract sgn $ DN.Finite coe ex
      coe = N.coefficient r
      ex = N.exponent r
      sgn = case r of
        A.RQuant q -> case A.qSide q of
          Debit -> D.Sign0
          Credit -> D.Sign1
        A.RZero _ -> D.Sign0
      d | fl == D.emptyFlags = dec
        | otherwise = error "repToConcrete: value out of range"

add :: Concrete -> Concrete -> Concrete
add (Concrete x) (Concrete y) = Concrete . compute $
  D.add x y

subt :: Concrete -> Concrete -> Concrete
subt (Concrete x) (Concrete y) = Concrete . compute $
  D.subtract x y

mult :: Concrete -> Concrete -> Concrete
mult (Concrete x) (Concrete y) = Concrete . compute $
  D.multiply x y

negate :: Concrete -> Concrete
negate (Concrete x) = Concrete . compute $ D.minus x
