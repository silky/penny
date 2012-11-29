-- | Parses reverse polish notation expressions. This module needs
-- much better error messages (right now it has none).
--
-- An RPN expression consists of operands and operators; a token is
-- either an operand or an operator. For example, in the expression @5
-- 4 +@, the @5@ and the @4@ are operands; the @+@ is an operator;
-- each of these three is a token.
module Penny.Liberty.Expressions.RPN (
  Operand(Operand),
  Operator(Unary, Binary),
  Token(TokOperand, TokOperator),
  process) where

import qualified Data.Foldable as Fdbl

-- | An operand; for example, in the expression @5 4 +@, @5@ and @4@
-- are operands.
newtype Operand a = Operand a deriving Show

-- | Operators; for example, in the expression @5 4 +@, @+@ is an
-- operator. Because this is RPN, there is no operator precedence.
data Operator a =
  Unary (a -> a)
  -- ^ Unary operators take only one operand (for example, a factorial
  -- operator).

  | Binary (a -> a -> a)
    -- ^ Binary operators take two operands (for example, an addition
    -- operator).

instance Show (Operator a) where
  show (Unary _) = "<unary operator>"
  show (Binary _) = "<binary operator>"

-- | A token is either an operator or an operand.
data Token a =
  TokOperand (Operand a)
  | TokOperator (Operator a)
  deriving Show


-- | Given an operator, and the stack of operands, process the
-- operator. When parsing an RPN expression, encountering an operator
-- at the front of the queue of tokens to be processed means that the
-- correct number of tokens (one, for a unary operator, or two, for a
-- binary operator) must be popped off the stack of operands. The
-- operator is then applied to the operands. For a binary operator,
-- the binary function is applied first to the operand that was lowest
-- on the stack, and then to the operand that was higher up on the
-- stack. The result of the operator is then pushed onto the top of
-- the stack.
--
-- This function fails if there were insufficient operands on the
-- stack to process the operator. If successful, returns the new
-- stack, with the processed operands removed and the result of the
-- operator pushed onto the top of the stack.
processOperator ::
  Operator a
  -> [Operand a]
  -> Maybe ([Operand a])
processOperator t ds = case t of
  (Unary f) -> case ds of
    [] -> Nothing
    (Operand x):xs -> return $ (Operand (f x)) : xs
  (Binary f) -> case ds of
    [] -> Nothing
    (Operand x):dss -> case dss of
      (Operand y):dsss ->
        return $ (Operand (f y x)) : dsss
      [] -> Nothing

-- | Adds an operand to the top of the stack.
processOperand ::
  Operand a
  -> [Operand a]
  -> [Operand a]
processOperand = (:)

-- | Processes the next token. Fails if the next token is an operator
-- and fails; otherwise, returns the new stack of operands.
processToken ::
  [Operand a]
  -> Token a
  -> Maybe ([Operand a])
processToken s tok = case tok of
  TokOperand d -> return (processOperand d s)
  TokOperator t -> processOperator t s

-- | Processes an entire input sequence of RPN tokens.
process ::
  Fdbl.Foldable l
  => l (Token a)
  -- ^ The tokens must be in the sequence from left to right in
  -- postfix order; for example, @5 4 -@ will yield @1@. Typically
  -- many appends will be required in order to build this sequence. If
  -- performance is a concern, you can use a Data.Sequence; if the
  -- list is small (as these lists will typically be) a regular list
  -- will do just fine.

  -> Maybe a
  -- ^ Fails if there is not exactly one operand remaining on the
  -- stack at the end of the parse, or if at any time there are
  -- insufficient operands on the stack to parse an
  -- operator. Otherwise, succeeds and returns the result.
process ls = do
  os <- Fdbl.foldlM processToken [] ls
  (top, rest) <- case os of
    (Operand x) : oss -> return (x, oss)
    _ -> Nothing
  case rest of
    [] -> return top
    _ -> Nothing