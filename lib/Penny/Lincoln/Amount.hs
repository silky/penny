module Penny.Lincoln.Amount where

import Penny.Lincoln.Concrete
import Penny.Lincoln.Rep
import Penny.Lincoln.Lane

data Amount a
  = ARep (Rep a)
  | AConcrete Concrete
  deriving Show

instance Functor Amount where
  fmap f r = case r of
    ARep a -> ARep (fmap f a)
    AConcrete c -> AConcrete c

instance HasConcrete (Amount a) where
  concrete r = case r of
    ARep a -> concrete a
    AConcrete c -> c

instance Laned (Amount a) where
  lane r = case r of
    ARep a -> lane a
    AConcrete c -> lane c