module Data.Record.Format where

import Prelude (id, (<>), class Show, show)
import Type.Prelude (Proxy (..))
import Type.Data.Symbol (class UnconsSymbol, class IsSymbol, SProxy (..), class AppendSymbol, reflectSymbol)
import Data.Record (get)

--------------------------------------------------------------------------------
-- * Format strings

foreign import kind Fmt -- ^ a format token is...
foreign import data Var :: Symbol -> Fmt -- ^ either a variable (to be replaced)
foreign import data Lit :: Symbol -> Fmt -- ^ or a literal

-- | A list of format tokens
foreign import kind FList
foreign import data FNil :: FList
foreign import data FCons :: Fmt -> FList -> FList

data FListProxy (l :: FList) = FListProxy

-- | Format a row with a (type-level) format string. If @row@ doesn't contain
--   all the necessary fields, constraint resolution fails
class Format (string :: Symbol) (row :: # Type) where
  format :: SProxy string -> Record row -> String

-- parse the format string and delegate the formatting to @FormatParsed@
instance formatParsedFormat ::
  ( Parse string parsed
  , FormatParsed parsed row
  ) => Format string row where
  format _ = formatParsed (FListProxy :: FListProxy parsed)

-- | Format a row with a list of format tokens. If @row@ doesn't contain
--   all the necessary fields, constraint resolution fails
class FormatParsed (strings :: FList) (row :: # Type) where
  formatParsed :: FListProxy strings -> Record row -> String

instance formatFNil :: FormatParsed FNil row where
  formatParsed _ _ = ""

instance formatVar ::
  ( IsSymbol key
  , RowCons key typ tail row
  , FormatParsed ks row
  , FormatVar typ
  ) => FormatParsed (FCons (Var key) ks) row where
  formatParsed _ row
    = var <> rest
    where var  = fmtVar (Proxy :: Proxy typ) (get (SProxy :: SProxy key) row)
          rest = formatParsed (FListProxy :: FListProxy ks) row

instance formatLit ::
  ( IsSymbol l
  , FormatParsed ks row
  ) => FormatParsed (FCons (Lit l) ks) row where
  formatParsed _ row
    = lit <> rest
    where lit  = reflectSymbol (SProxy :: SProxy l)
          rest = formatParsed (FListProxy :: FListProxy ks) row

-- | Formatting variables - we don't want to show the quotes around strings, so
--   we treat them specially
class FormatVar a where
  -- the @Proxy a@ seems redundant, but it's needed here, otherwise the
  -- @formatVar@ instance above tries to always match the second instance (I'm
  -- not sure why - this is just a workaround)
  fmtVar :: Proxy a -> a -> String

instance aFmtVar :: FormatVar String where
  fmtVar _ = id

instance bFmtVar :: Show a => FormatVar a where
  fmtVar _ = show

--------------------------------------------------------------------------------
-- Parsing

class Parse (i :: Symbol) (o :: FList) | i -> o

instance aParse :: Parse "" FNil
instance bParse :: (UnconsSymbol i h t, ParseLit h t o) => Parse i o

-- | Parse literals. @h@ is the current character, @t@ is the remaining string
class ParseLit (h :: Symbol) (t :: Symbol) (o :: FList) | h t -> o

instance aParseLitNil :: ParseLit o "" (FCons (Lit o) FNil)

-- when we find a '{' character, call @ParseVar@
instance bParseLitVar ::
  ( UnconsSymbol t h' t'
  , ParseVar h' t' (Var match) rest
  , Parse rest pRest
  ) => ParseLit "{" t (FCons (Lit "") (FCons (Var match) pRest))

instance cParseLit ::
  ( Parse i (FCons (Lit l) fs)
  , AppendSymbol c l cl
  ) => ParseLit c i (FCons (Lit cl) fs)

-- | Parse variables. Returns the symbol between {}s and the remaining string
--   after the closing '}'
class ParseVar (h :: Symbol) (t :: Symbol) (var :: Fmt) (rest :: Symbol) | h t -> var rest

instance aParseVar :: ParseVar "" a (Var "") ""
instance bParseVar :: ParseVar "}" i (Var "") i
instance cParseVar :: ParseVar curr "" (Var curr) ""

instance dParseVar ::
  ( UnconsSymbol t h' t'
  , ParseVar h' t' (Var var) rest
  , AppendSymbol h var var'
  ) => ParseVar h t (Var var') rest

parse :: forall i o. Parse i o => SProxy i -> FListProxy o
parse _ = FListProxy