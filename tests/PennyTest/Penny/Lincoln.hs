module PennyTest.Penny.Lincoln where

import qualified Test.Framework as TF
import qualified PennyTest.Penny.Lincoln.Bits as B

tests :: TF.Test
tests = TF.testGroup "PennyTest.Penny.Lincoln"
  [ B.tests ]