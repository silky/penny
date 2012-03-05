module Penny.Copper.Item where

import Control.Applicative ((<$>), (<*>), (<$))
import Control.Monad ( liftM )
import Text.Parsec (getPosition, sourceLine, (<|>), char)
import Text.Parsec.Text ( Parser )

import qualified Penny.Copper.Comments.Multiline as CM
import qualified Penny.Copper.Comments.SingleLine as CS
import qualified Penny.Copper.DateTime as DT
import qualified Penny.Lincoln.Meta as M
import qualified Penny.Copper.Qty as Q
import Penny.Copper.Price ( price )
import Penny.Copper.Transaction ( transaction )
import Penny.Lincoln.Boxes (TransactionBox, PriceBox)


data Item = Transaction TransactionBox
          | Price PriceBox
          | Multiline CM.Multiline
          | SingleLine CS.Comment
          | BlankLine
          deriving Show

itemWithLineNumber ::
  M.Filename
  -> DT.DefaultTimeZone
  -> Q.RadGroup
  -> Parser (M.Line, Item)
itemWithLineNumber fn dtz rg = (,)
  <$> ((M.Line . sourceLine) <$> getPosition)
  <*> parseItem fn dtz rg

parseItem ::
  M.Filename
  -> DT.DefaultTimeZone
  -> Q.RadGroup
  -> Parser Item
parseItem fn dtz rg = let
   bl = BlankLine <$ char '\n'
   t = Transaction <$> transaction fn dtz rg
   p = Price <$> price dtz rg
   cm = Multiline <$> CM.multiline
   co = SingleLine <$> CS.comment
   in (bl <|> t <|> p <|> cm <|> co)
