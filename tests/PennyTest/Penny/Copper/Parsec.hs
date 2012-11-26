module PennyTest.Penny.Copper.Parsec where

import Control.Monad.Exception.Synchronous as Ex
import Control.Monad.Trans.Class (lift)
import Text.Parsec (parse)
import Text.Parsec.Text (Parser)
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck (Gen)
import qualified Test.QuickCheck.Property as QP
import qualified PennyTest.Penny.Copper.Gen.Parsers as P
import qualified Penny.Copper.Parsec as C
import qualified Penny.Copper.Lincoln as L

import Data.Text (Text)

tests :: Test
tests = testGroup "PennyTest.Penny.Copper.Parsec"
  [ pTest "lvl1SubAcct"
    C.lvl1SubAcct P.lvl1SubAcct

  , pTest "lvl1FirstSubAcct"
    C.lvl1FirstSubAcct P.lvl1FirstSubAcct

  , pTest "lvl1OtherSubAcct"
    C.lvl1OtherSubAcct P.lvl1OtherSubAcct

  , pTest "lvl1Acct"
    C.lvl1Acct P.lvl1Acct

  , pTest "quotedLvl1Acct"
    C.quotedLvl1Acct P.quotedLvl1Acct

  , pTest "lvl2FirstSubAcct"
    C.lvl2FirstSubAcct P.lvl2FirstSubAcct

  , pTest "lvl2OtherSubAcct"
    C.lvl2OtherSubAcct P.lvl2OtherSubAcct

  , pTest "lvl2Acct"
    C.lvl2Acct P.lvl2Acct

  , pTest "ledgerAcct"
    C.ledgerAcct P.ledgerAcct

  , pTest "lvl1Cmdty"
    C.lvl1Cmdty P.lvl1Cmdty

  , pTest "quotedLvl1Cmdty"
    C.quotedLvl1Cmdty
    (fmap (\(P.QuotedLvl1Cmdty c x) -> (c, x)) P.quotedLvl1Cmdty)

  , pTest "lvl2Cmdty"
    C.lvl2Cmdty
    (fmap (\(P.Lvl2Cmdty c x) -> (c, x)) P.lvl2Cmdty)

  , pTest "lvl3Cmdty"
    C.lvl3Cmdty
    (fmap (\(P.Lvl3Cmdty c x) -> (c, x)) P.lvl3Cmdty)

  , pTestT "quantity"
    C.quantity P.quantity

  ]


pTestByT
  :: Show a
  => (a -> a -> Bool)
  -> String
  -> Parser a
  -> P.GenT (a, Text)
  -> Test
pTestByT eq s p g = testProperty s t
  where
    t = Ex.resolveT return $ do
      (r, txt) <- g
      case parse p "" txt of
        Left e ->
          let msg = "failed to parse text: " ++ show e
          in return $ QP.failed { QP.reason = msg }
        Right parsed ->
          if eq parsed r
          then return QP.succeeded
          else
            let msg = "result not equal. Parsed result: "
                      ++ show parsed
                      ++ " expected result: " ++ show r
            in return $ QP.failed { QP.reason = msg }

pTestT
  :: (Show a, Eq a)
  => String
  -> Parser a
  -> P.GenT (a, Text)
  -> Test
pTestT = pTestByT (==)


pTestBy
  :: Show a
  => (a -> a -> Bool)
  -> String
  -> Parser a
  -> Gen (a, Text)
  -> Test
pTestBy eq s p g = pTestByT eq s p (lift g)

pTest
  :: (Show a, Eq a)
  => String
  -> Parser a
  -> Gen (a, Text)
  -> Test
pTest = pTestBy (==)

