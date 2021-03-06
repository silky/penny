module Penny.Brenner.Merge (mode) where

import Control.Applicative
import Control.Monad (guard)
import qualified Control.Monad.Trans.State as St
import Data.List (find, sortBy, foldl')
import qualified Data.Map as M
import Data.Maybe (mapMaybe, isNothing, fromMaybe)
import Data.Monoid (First(..), mconcat)
import qualified Data.Text as X
import qualified System.Console.MultiArg as MA
import qualified Penny.Copper as C
import qualified Penny.Copper.Render as R
import qualified Penny.Lincoln as L
import qualified Penny.Liberty as Ly
import qualified Penny.Lincoln.Queries as Q
import qualified Penny.Brenner.Types as Y
import qualified Penny.Brenner.Util as U
import qualified Data.Sums as S

type NoAuto = Bool

data Arg
  = APos String
  | ANoAuto
  | AOutput (X.Text -> IO ())

instance Eq Arg where
  APos l == APos r = l == r
  ANoAuto == ANoAuto = True
  _ == _ = False

toPosArg :: Arg -> Maybe String
toPosArg a = case a of { APos s -> Just s; _ -> Nothing }

toOutput :: Arg -> Maybe (X.Text -> IO ())
toOutput a = case a of { AOutput x -> Just x; _ -> Nothing }

mode :: Y.Mode
mode mayFa = MA.modeHelp
  "merge"
  help
  (processor mayFa)
  opts
  MA.Intersperse
  (return . APos)
  where
    opts = [ MA.OptSpec ["no-auto"] "n" (MA.NoArg ANoAuto)
           , fmap AOutput Ly.output
           ]

processor :: Maybe Y.FitAcct -> [Arg] -> IO ()
processor mayFa as = do
  fa <- U.getFitAcct mayFa
  doMerge fa
          (ANoAuto `elem` as)
          (Ly.processOutput . mapMaybe toOutput $ as)
          (mapMaybe toPosArg as)

doMerge
  :: Y.FitAcct
  -> NoAuto
  -> (X.Text -> IO ())
  -- ^ Function to handle the output
  -> [String]
  -- ^ Ledger filenames to open
  -> IO ()
doMerge acct noAuto printer ss = do
  dbLs <- U.loadDb (Y.AllowNew False) (Y.dbLocation acct)
  l <- C.open ss
  let dbWithEntry = fmap (pairWithEntry acct) . M.fromList $ dbLs
      (l', db') = changeItems acct
                  l (filterDb (Y.pennyAcct acct) dbWithEntry l)
      newTxns = createTransactions noAuto acct l dbLs db'
      final = l' ++ newTxns
  case mapM (R.item Nothing) (map C.stripMeta final) of
    Nothing -> fail "Could not render final ledger."
    Just txts ->
      let txt = X.concat txts
      in txt `seq` printer txt


help :: String -> String
help pn = unlines
  [ "usage: " ++ pn ++ " merge: merges new transactions from database"
  , "to ledger file."
  , "usage: penny-fit merge [options] FILE..."
  , "Results are printed to standard output. If no FILE, or if FILE is -,"
  , "read standard input."
  , ""
  , "Options:"
  , "  -n, --no-auto - do not automatically assign payees and accounts"
  , "  -o, --output FILENAME - send output to FILENAME"
  , "     (default: send to standard output)"
  , "  -h, --help - show help and exit"
  ]

-- | Removes all Brenner postings that already have a Penny posting
-- with the correct uNumber.
filterDb :: Y.PennyAcct -> DbWithEntry -> [C.LedgerItem] -> DbWithEntry
filterDb ax m l = M.difference m ml
  where
    ml = M.fromList
       . flip zip (repeat ())
       . mapMaybe toUNum
       . filter inPennyAcct
       . concatMap L.transactionToPostings
       . ( let cn = const Nothing
           in mapMaybe (S.caseS4 Just cn cn cn))
       $ l
    inPennyAcct p = Q.account p == (Y.unPennyAcct ax)
    toUNum p = getUNumberFromTags . Q.tags $ p

-- | Gets the first UNumber from a list of Tags.
getUNumberFromTags :: L.Tags -> Maybe Y.UNumber
getUNumberFromTags =
  getFirst
  . mconcat
  . map First
  . map getUNumberFromTag
  . L.unTags

-- | Examines a tag to see if it is a uNumber. If so, returns the
-- UNumber. Otherwise, returns Nothing.
getUNumberFromTag :: L.Tag -> Maybe Y.UNumber
getUNumberFromTag (L.Tag x) = do
  (f, r) <- X.uncons x
  guard (f == 'U')
  case reads . X.unpack $ r of
    (y, ""):[] -> return $ Y.UNumber y
    _ -> Nothing


-- | Changes a single Item.
changeItem
  :: Y.FitAcct
  -> C.LedgerItem
  -> St.State DbWithEntry C.LedgerItem
changeItem acct =
  S.caseS4 (fmap S.S4a . changeTransaction acct)
           (return . S.S4b) (return . S.S4c) (return . S.S4d)


-- | Changes all postings that match an AmexTxn to assign them the
-- proper UNumber. Returns a list of changed items, and the DbMap of
-- still-unassigned AmexTxns.
changeItems
  :: Y.FitAcct
  -> [C.LedgerItem]
  -> DbWithEntry
  -> ([C.LedgerItem], DbWithEntry)
changeItems acct l = St.runState (mapM (changeItem acct) l)


changeTransaction
  :: Y.FitAcct
  -> L.Transaction
  -> St.State DbWithEntry L.Transaction
changeTransaction acct txn =
  (\tl es -> L.Transaction (tl, es))
  <$> pure (fst . L.unTransaction $ txn)
  <*> L.traverseEnts (inspectAndChange acct
                      (fst . L.unTransaction $ txn))
                      (snd . L.unTransaction $ txn)

-- | Inspects a posting to see if it is an Amex posting and, if so,
-- whether it matches one of the remaining AmexTxns. If so, then
-- changes the transaction's UNumber, and remove that UNumber from the
-- DbMap. If the posting alreay has a Number (UNumber or otherwise)
-- skips it.
inspectAndChange
  :: Y.FitAcct
  -> L.TopLineData
  -> L.Ent L.PostingData
  -> St.State DbWithEntry L.PostingData
inspectAndChange acct tld p = do
  m <- St.get
  case findMatch acct tld p m of
    Nothing -> return (L.meta p)
    Just (n, m') ->
      let c = L.pdCore . L.meta $ p
          L.Tags oldTags = L.pTags c
          tags' = L.Tags (oldTags ++ [newLincolnUNumber n])
          c' = c { L.pTags = tags' }
          p' = (L.meta p) { L.pdCore = c' }
      in St.put m' >> return p'

newLincolnUNumber :: Y.UNumber -> L.Tag
newLincolnUNumber a =
  L.Tag ('U' `X.cons` (X.pack . show . Y.unUNumber $ a))


-- | Searches a DbMap for an AmexTxn that matches a given posting. If
-- a match is found, returns the matching UNumber and a new DbMap that
-- has the match removed.
findMatch
  :: Y.FitAcct
  -> L.TopLineData
  -> L.Ent L.PostingData
  -> DbWithEntry
  -> Maybe (Y.UNumber, DbWithEntry)
findMatch acct tl p m = fmap toResult findResult
  where
    findResult = find (pennyTxnMatches acct tl p)
                 . M.toList $ m
    toResult (u, (_, _)) = (u, M.delete u m)

-- | Pairs each association in a DbMap with an Entry representing the
-- transaction's entry in the ledger.
pairWithEntry :: Y.FitAcct -> Y.Posting -> (Y.Posting, L.Entry L.Qty)
pairWithEntry acct p = (p, en)
  where
    en = L.Entry dc (L.Amount qty cty)
    dc = Y.translate (Y.incDec p) (Y.translator acct)
    qty = U.parseQty (Y.amount p)
    cty = Y.unCurrency . Y.currency $ acct

type DbWithEntry = M.Map Y.UNumber (Y.Posting, L.Entry L.Qty)

-- | Does the given Penny transaction match this posting? Makes sure
-- that the account, quantity, date, commodity, and DrCr match, and
-- that the posting does not have a number (it's OK if the transaction
-- has a number.)
pennyTxnMatches
  :: Y.FitAcct
  -> L.TopLineData
  -> L.Ent L.PostingData
  -> (a, (Y.Posting, L.Entry L.Qty))
  -> Bool
pennyTxnMatches acct tl pstg (_, (a, e)) =
  mA && noFlag && mQ && mDC && mDate && mCmdty
  where
    p = L.pdCore . L.meta $ pstg
    mA = L.pAccount p == (Y.unPennyAcct . Y.pennyAcct $ acct)
    mQ = L.equivalent (eitherToQty . L.entry $ pstg)
                      (L.qty . L.amount $ e)
    mDC = (L.drCr e) == (either L.drCr L.drCr . L.entry $ pstg)
    mDate = (L.day . L.tDateTime . L.tlCore $ tl) == (Y.unDate . Y.date $ a)
    noFlag = isNothing . L.pNumber $ p
    mCmdty = (eitherToCmdty . L.entry $ pstg)
             == (Y.unCurrency . Y.currency $ acct)


eitherToCmdty :: Either (L.Entry a) (L.Entry b) -> L.Commodity
eitherToCmdty = either (L.commodity . L.amount) (L.commodity . L.amount)

eitherToQty :: Either (L.Entry L.QtyRep) (L.Entry L.Qty) -> L.Qty
eitherToQty = either (L.toQty . L.qty . L.amount)
                     (L.toQty . L.qty . L.amount)

-- | Creates a new transaction corresponding to a given AmexTxn. Uses
-- the Amex payee if that string is non empty; otherwise, uses the
-- Amex description for the payee.
newTransaction
  :: NoAuto
  -> Y.FitAcct
  -> UNumberLookupMap
  -> PyeLookupMap
  -> (Y.UNumber, (Y.Posting, L.Entry L.Qty))
  -> L.Transaction
newTransaction noAuto acct mu mp (u, (a, e))
  = L.Transaction (tld, ents) where
  tld = L.TopLineData tlc Nothing Nothing
  tlc = (L.emptyTopLineCore (L.dateTimeMidnightUTC . Y.unDate . Y.date $ a))
        { L.tPayee = Just pa }
  (pa, ac) = if noAuto then (dfltPye, dfltAcct)
    else ( fromMaybe dfltPye guessedPye,
           fromMaybe dfltAcct guessedAcct)
  (guessedPye, guessedAcct) = guessInfo (Y.toLincolnPayee acct) mu mp a
  dfltPye = getPye (Y.desc a) (Y.payee a)
  dfltAcct = Y.unDefaultAcct . Y.defaultAcct $ acct
  getPye = Y.toLincolnPayee acct
  pennyAcct = Y.unPennyAcct . Y.pennyAcct $ acct
  p1data = L.PostingData p1core Nothing Nothing
  p2data = L.PostingData p2core Nothing Nothing
  p1core = (L.emptyPostingCore pennyAcct)
           { L.pTags = L.Tags [newLincolnUNumber u]
           , L.pSide = Just $ Y.side acct
           , L.pSpaceBetween = Just $ Y.spaceBetween acct
           }
  p2core = L.emptyPostingCore ac
  ents = L.rEnts (Y.unCurrency . Y.currency $ acct) (L.drCr e)
                 (Left . L.qtyToRep gs . L.qty . L.amount $ e, p1data)
                 [] p2data
  gs = Y.qtySpec acct

-- | Creates new transactions for all the items remaining in the
-- DbMap. Appends a blank line after each one.
createTransactions
  :: NoAuto
  -> Y.FitAcct
  -> [C.LedgerItem]
  -> Y.DbList
  -> DbWithEntry
  -> [C.LedgerItem]
createTransactions noAuto acct led dbLs db =
  concatMap (\i -> [i, S.S4d C.BlankLine])
  . map S.S4a
  . map (newTransaction noAuto acct mu mp)
  . M.assocs
  $ db
  where
    mu = makeUNumberLookup (Y.toLincolnPayee acct) dbLs
    mp = makePyeLookupMap (Y.pennyAcct acct) led

-- | Maps financial institution postings to UNumbers. The key is the
-- Lincoln Payee of the financial institution posting, which is
-- computed using the toLincolnPayee function in the FitAcct.  The
-- UNumbers are in a list, with UNumbers from most recent financial
-- institution postings first.
type UNumberLookupMap = M.Map L.Payee [Y.UNumber]

-- | Create a UNumberLookupMap from a DbWithEntry. Financial
-- institution postings with higher U-numbers will come first.
makeUNumberLookup
  :: (Y.Desc -> Y.Payee -> L.Payee)
  -> Y.DbList
  -> UNumberLookupMap
makeUNumberLookup toPye = foldl' ins M.empty . map f . sortBy g
  where
    ins m (k, v) = M.alter alterer k m
      where alterer Nothing = Just [v]
            alterer (Just ls) = Just $ v:ls
    f (u, p) = (toPye (Y.desc p) (Y.payee p), u)
    g (_, p1) (_, p2) = compare (Y.date p1) (Y.date p2)

-- | Given a list of keys, find the first key that is in the
-- map. Returns Nothing if no key is in the map.
findFirstKey :: Ord k => M.Map k v -> [k] -> Maybe v
findFirstKey _ [] = Nothing
findFirstKey m (k:ks) = case M.lookup k m of
  Nothing -> findFirstKey m ks
  Just v -> Just v

-- | Maps UNumbers to payees and accounts from the ledger.
type PyeLookupMap = M.Map Y.UNumber (Maybe L.Payee, Maybe L.Account)

-- | Makes a payee lookup map. Puts those postings which match the
-- PennyAcct and have a UNumber into the map. (If two postings match
-- the PennyAcct and have the same UNumber, the one that appears later
-- in the ledger file will be in the map.)
makePyeLookupMap :: Y.PennyAcct -> [C.LedgerItem] -> PyeLookupMap
makePyeLookupMap a l
  = M.fromList . mapMaybe f . concatMap L.transactionToPostings
    . mapMaybe toPstg
    $ l
  where
    f pstg = do
      guard $ (Q.account pstg) == Y.unPennyAcct a
      u <- getUNumberFromTags . Q.tags $ pstg
      let tailents = L.tailEnts . snd . L.unPosting $ pstg
          ac = case tailents of
            (x, []) -> Just (L.pAccount . L.pdCore . L.meta $ x)
            _ -> Nothing
      return (u, (Q.payee pstg, ac))
    toPstg = let cn = const Nothing in S.caseS4 Just cn cn cn

-- | Given a UNumber and the maps, looks up the payee and account
-- information from previous transactions if this information is
-- available.
guessInfo
  :: (Y.Desc -> Y.Payee -> L.Payee)
  -> UNumberLookupMap
  -> PyeLookupMap
  -> Y.Posting
  -> (Maybe L.Payee, Maybe L.Account)
guessInfo getPye mu mp p = fromMaybe (Nothing, Nothing) $ do
  let pstgPayee = getPye (Y.desc p) (Y.payee p)
  unums <- M.lookup pstgPayee mu
  findFirstKey mp unums
