{-# OPTIONS_GHC -fno-warn-missing-signatures
                -fno-warn-orphans #-}
module Copper.Render where

import Control.Applicative ((<*))
import qualified Copper.Gen.Parsers as G
import qualified Penny.Copper.Interface as I
import qualified Penny.Copper.Render as R
import qualified Penny.Copper.Parsec as P
import qualified Penny.Lincoln as L
import Penny.Lincoln ((==~))
import qualified Text.Parsec as Ps
import qualified Text.Parsec.Text as Ps
import qualified Test.QuickCheck as Q
import qualified Test.QuickCheck.Property as QCP
import Test.QuickCheck (Gen, arbitrary)
import Data.Text (Text)
import Test.Tasty.QuickCheck (testProperty)
import Test.Tasty (testGroup, TestTree)

renParse
  :: (Eq a, Show a)
  => (a -> Maybe Text)
  -> Ps.Parser a
  -> Gen (a, b)
  -> Q.Property
renParse r p g = Q.forAll (fmap fst g) $ \ a ->
  doParse r p a

doParseWithPdct
  :: Show a
  => (a -> a -> Bool)
  -> (a -> Maybe Text)
  -> Ps.Parser a
  -> a
  -> QCP.Result
doParseWithPdct pdct r p a =
  case r a of
    Nothing -> QCP.failed { QCP.reason = "render failed: "
                            ++ show a }
    Just rend -> case Ps.parse (p <* Ps.eof) "" rend of
      Left e -> QCP.failed { QCP.reason = "parse failed: "
                             ++ show e }
      Right g ->
        if pdct g a
        then QCP.succeeded
        else QCP.failed
             { QCP.reason = "parsed not equal to original. "
               ++ "Original: " ++ show a ++ " parsed: "
               ++ show g }

doParse
  :: (Eq a, Show a)
  => (a -> Maybe Text)
  -> Ps.Parser a
  -> a
  -> QCP.Result
doParse = doParseWithPdct (==)

doParseEv
  :: (L.Equivalent a, Show a)
  => (a -> Maybe Text)
  -> Ps.Parser a
  -> a
  -> QCP.Result
doParseEv = doParseWithPdct (==~)

prop_quotedLvl1Acct =
  renParse R.quotedLvl1Acct P.quotedLvl1Acct G.quotedLvl1Acct

prop_lvl2Acct =
  renParse R.lvl2Acct P.lvl2Acct G.lvl2Acct

prop_ledgerAcct =
  renParse R.ledgerAcct P.ledgerAcct G.ledgerAcct

prop_quotedLvl1Cmdty =
  renParse R.quotedLvl1Cmdty P.quotedLvl1Cmdty
  (fmap (\ (G.QuotedLvl1Cmdty c _) -> (c, ())) G.quotedLvl1Cmdty)

prop_lvl2Cmdty =
  renParse R.lvl2Cmdty P.lvl2Cmdty
  (fmap (\(G.Lvl2Cmdty c _) -> (c, ())) G.lvl2Cmdty)

prop_lvl3Cmdty =
  renParse R.lvl3Cmdty P.lvl3Cmdty
  (fmap (\(G.Lvl3Cmdty c _) -> (c, ())) G.lvl3Cmdty)


prop_qtyRep = do
  qr <- arbitrary
  return $ doParseEv (fmap Just R.qtyRep) P.qtyRep qr

prop_amount = do
  cy <- G.genCmdty
  qr <- G.ast
  let rend (am, sd, sb) = R.amount Nothing (Just sd) (Just sb) (Left am)
  r <- fmap (\ ((am, _), sb, sd) -> (am, sd, sb)) (G.amount cy qr)
  return $ doParseEv rend P.amount r

prop_comment =
  renParse R.comment P.comment G.comment

prop_dateTime =
  renParse (fmap Just R.dateTime) P.dateTime G.dateTime

prop_entry = do
  cy <- G.genCmdty
  dc <- G.drCr
  qr <- G.ast
  let rend (iEn, iSd, iSb) = R.entry Nothing (Just iSd) (Just iSb)
                                     (Left iEn)
  ((en, _), sb, sd) <- G.entry cy dc qr
  return $ doParseEv rend P.entry (en, sd, sb)

prop_flag =
  renParse R.flag P.flag G.flag

prop_postingMemoLine = do
  i <- Q.choose (0,4)
  (t, _) <- G.postingMemoLine
  let rend = R.postingMemoLine i
  return $ doParse rend P.postingMemoLine t

prop_postingMemo = do
  b <- arbitrary
  (m, _) <- G.postingMemo
  let rend = R.postingMemo b
  return $ doParse rend P.postingMemo m

prop_transactionMemoLine =
  renParse R.transactionMemoLine P.transactionMemoLine G.transactionMemoLine

prop_transactionMemo =
  renParse R.transactionMemo (fmap snd P.transactionMemo)
           G.transactionMemo

prop_number =
  renParse R.number P.number G.number

prop_quotedLvl1Payee =
  renParse R.quotedLvl1Payee P.quotedLvl1Payee G.quotedLvl1Payee

prop_lvl2Payee =
  renParse R.lvl2Payee P.lvl2Payee G.lvl2Payee

prop_price = do
  (pr, _) <- G.price
  return $ doParseWithPdct priceEq R.price P.price pr

prop_tag =
  renParse R.tag P.tag G.tag

prop_tags =
  renParse R.tags P.tags G.tags

prop_topLineCore =
  renParse R.topLine (fmap toTopLine P.topLine) G.topLineCore

toTopLine :: I.ParsedTopLine -> L.TopLineCore
toTopLine (I.ParsedTopLine dt nu fl pa me _) =
  L.TopLineCore dt nu fl pa (fmap fst me)


prop_transaction = do
  let rend = R.transaction Nothing
      toPair (tl, es) = (toTopLine tl, fmap fst es)
  (genTx, _) <- G.transaction
  return $ doParseEv rend (fmap toPair P.transaction) genTx

priceEq :: L.PricePoint -> L.PricePoint -> Bool
priceEq (L.PricePoint xdt xpr xsd xsb _)
        (L.PricePoint ydt ypr ysd ysb _)
  = xdt == ydt && xpr ==~ ypr && xsd == ysd && xsb == ysb

testTree :: TestTree
testTree = testGroup "Render"
  [ testProperty "prop_quotedLvl1Acct" prop_quotedLvl1Acct
  , testProperty "prop_lvl2Acct" prop_lvl2Acct
  , testProperty "prop_ledgerAcct" prop_ledgerAcct
  , testProperty "prop_quotedLvl1Cmdty" prop_quotedLvl1Cmdty
  , testProperty "prop_lvl2Cmdty" prop_lvl2Cmdty
  , testProperty "prop_lvl3Cmdty" prop_lvl3Cmdty
  , testProperty "prop_qtyRep" prop_qtyRep
  , testProperty "prop_amount" prop_amount
  , testProperty "prop_comment" prop_comment
  , testProperty "prop_dateTime" prop_dateTime
  , testProperty "prop_entry" prop_entry
  , testProperty "prop_flag" prop_flag
  , testProperty "prop_postingMemoLine" prop_postingMemoLine
  , testProperty "prop_postingMemo" prop_postingMemo
  , testProperty "prop_transactionMemoLine" prop_transactionMemoLine
  , testProperty "prop_transactionMemo" prop_transactionMemo
  , testProperty "prop_number" prop_number
  , testProperty "prop_quotedLvl1Payee" prop_quotedLvl1Payee
  , testProperty "prop_lvl2Payee" prop_lvl2Payee
  , testProperty "prop_price" prop_price
  , testProperty "prop_tag" prop_tag
  , testProperty "prop_tags" prop_tags
  , testProperty "prop_topLineCore" prop_topLineCore
  , testProperty "prop_transaction" prop_transaction
  ]
