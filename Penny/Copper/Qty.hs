module Penny.Copper.Qty (
  -- * Setting the radix and separator characters
  RadGroup, periodComma, periodSpace, commaPeriod,
  commaSpace,
  
  -- * Parsing quantities
  qtyUnquoted,
  qtyQuoted) where

import Control.Applicative ((<$>), (<*>), (<$), (*>), optional)
import qualified Data.Decimal as D
import qualified Data.List.NonEmpty as NE
import Text.Parsec ( char, (<|>), many, many1, try, (<?>), 
                     sepBy1, digit, between)
import qualified Text.Parsec as P
import Text.Parsec.Text ( Parser )

import Penny.Lincoln.Bits.Qty ( Qty, partialNewQty )

data Radix = RComma | RPeriod deriving Show
data Grouper = GComma | GPeriod | GSpace deriving Show

data RadGroup = RadGroup Radix Grouper deriving Show

-- | Radix is period, grouping is comma
periodComma :: RadGroup
periodComma = RadGroup RPeriod GComma

-- | Radix is period, grouping is space
periodSpace :: RadGroup
periodSpace = RadGroup RPeriod GSpace

-- | Radix is comma, grouping is period
commaPeriod :: RadGroup
commaPeriod = RadGroup RComma GPeriod

-- | Radix is comma, grouping is space
commaSpace :: RadGroup
commaSpace = RadGroup RComma GSpace

parseRadix :: Radix -> Parser ()
parseRadix r = () <$ char c <?> "radix point" where
  c = case r of RComma -> ','; RPeriod -> '.'

parseGrouper :: Grouper -> Parser ()
parseGrouper g = () <$ char c <?> "grouping character" where
  c = case g of
    GComma -> ','
    GPeriod -> '.'
    GSpace -> ' '

{- a BNF style specification for numbers.

<radix> ::= (as specified)
<grouper> ::= (as specified)
<digit> ::= "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "0"
<digits> ::= <digit> | <digit> <digits>
<firstGroups> ::= <digits> <grouper> <digits>
<nextGroup> ::= <grouper> <digits>
<nextGroups> ::= <nextGroup> | <nextGroup> <nextGroups>
<allGroups> ::= <firstGroups> | <firstGroups> <nextGroups>
<whole> ::= <allGroups> | <digits>
<fractional> ::= <digits>
<number> ::= <whole>
             | <whole> <radix>
             | <whole> <radix> <fractional>
             | <radix> <fractional>
-}

wholeGrouped :: Grouper -> Parser String
wholeGrouped g = p <$> group1 <*> optional groupRest <?> e where 
  e = "whole number"
  group1 = many1 digit
  groupRest = parseGrouper g *> sepBy1 (many1 digit) (parseGrouper g)
  p g1 gr = case gr of
    Nothing -> g1
    (Just groups) -> g1 ++ (concat groups)

wholeNonGrouped :: Parser String
wholeNonGrouped = many1 digit

fractional :: Parser String
fractional = many1 digit

data NumberStr = Whole String
               | WholeRad String
               | WholeRadFrac String String
               | RadFrac String

startsRad :: Radix -> Parser (Maybe String)
startsRad r = parseRadix r *> (optional (many1 P.digit))

fractionalOnly :: Radix -> Parser String
fractionalOnly r = parseRadix r *> many1 P.digit

numberStrGrouped :: Radix -> Grouper -> Parser NumberStr
numberStrGrouped r g = startsWhole <|> fracOnly <?> e where
  e = "quantity, with optional grouping"
  startsWhole = p <?> "whole number" where
    p = do
      wholeStr <- wholeGrouped g
      mayRad <- optional (parseRadix r)
      case mayRad of
        Nothing -> return $ Whole wholeStr
        Just _ -> do
          mayFrac <- optional $ many1 P.digit
          case mayFrac of
            Nothing -> return $ WholeRad wholeStr
            Just frac -> return $ WholeRadFrac wholeStr frac
  fracOnly = RadFrac <$> fractionalOnly r

numberStrNonGrouped :: Radix -> Parser NumberStr
numberStrNonGrouped r = startsWhole <|> fracOnly <?> e where
  e = "quantity, no grouping"
  startsWhole = p <?> "whole number" where
    p = do
      wholeStr <- wholeNonGrouped
      mayRad <- optional (parseRadix r)
      case mayRad of
        Nothing -> return $ Whole wholeStr
        Just _ -> do
          mayFrac <- optional $ many1 P.digit
          case mayFrac of
            Nothing -> return $ WholeRad wholeStr
            Just frac -> return $ WholeRadFrac wholeStr frac
  fracOnly = RadFrac <$> fractionalOnly r

toDecimal :: NumberStr -> D.Decimal
toDecimal s = read d where
  d = case s of
    Whole str -> str
    WholeRad str -> str
    WholeRadFrac wh fr -> wh ++ "." ++ fr
    RadFrac fr -> '.':fr

-- | Unquoted quantity. These include no spaces, regardless of what
-- the grouping character is.
qtyUnquoted :: RadGroup -> Parser Qty
qtyUnquoted (RadGroup r g) = f <$> p where
  f = (partialNewQty . toDecimal)
  p = case g of
    GSpace -> numberStrNonGrouped r
    _ -> numberStrGrouped r g

-- | Parse quoted quantity. It can include spaces, if the grouping
-- character is a space. However these must be quoted when in a Ledger
-- file (from the command line they need not be quoted). The quote
-- character is a caret, @^@.
qtyQuoted :: RadGroup -> Parser Qty
qtyQuoted (RadGroup r g) = between (char '^') (char '^') p where
  p = (partialNewQty . toDecimal) <$> numberStrGrouped r g

{-
numberStr :: Radix -> Separator -> Parser NumberStr
numberStr r s = startsWhole <|> fractionalOnly <?> e where
  e = "quantity"
  startsWhole = f <$> whole <*> startsRad r where
    f sWhole mayFrac = case mayFrac of
      Nothing -> Whole sWhole
      Just frac -> Whole
-}

{-
newtype Radix = Radix { unRadix :: Char }
newtype Separator = Separator { unSeparator :: Char }

radixAndSeparator :: Char -> Char -> (Radix, Separator)
radixAndSeparator r s =
  if r == s
  then error "radix and separator must be different characters"
  else (Radix r, Separator s)

radix :: Radix -> Parser Char
radix (Radix r) = char r >> return '.'

qtyDigit :: Separator -> Parser Char
qtyDigit (Separator separator) = digit <|> (char separator >> digit)

qty :: Radix -> Separator -> Parser Qty
qty rdx sep = let
  digitRun = do
    c <- digit
    cs <- many (qtyDigit sep)
    return (c : cs)
  withPoint = do
    l <- digitRun
    p <- radix rdx
    r <- digitRun
    return (l ++ (p : r))
  withoutPoint = digitRun
  in do
    s <- try withPoint <|> withoutPoint
    let d = read s
    return $ partialNewQty d

-}
