#!/usr/bin/env runhaskell
-- vim: filetype=haskell
--
-- Generate c2hs FFI binding hooks
--
-- Based on: https://github.com/Rufflewind/blas-hs/blob/f8e90b26bc9865618802dce9ccf21fc2b5c032be/tools/generate-ffi
--
module Main (main) where

import Data.Char                                                    ( toUpper )
import Data.Functor                                                 ( (<$>) )
import Data.List                                                    ( intercalate )
import Data.Monoid                                                  ( (<>) )
import Text.Printf                                                  ( printf )


main :: IO ()
main = do
  let
      docs :: Int -> [String]
      docs l  = [ printf "For more information see the cuBLAS Level-%d function reference:" l
                , ""
                , printf "<http://docs.nvidia.com/cuda/cublas/index.html#cublas-level-%d-function-reference>" l
                , ""
                ]
      l1exps  = []
      l2exps  = [ "Operation(..)"
                , "Fill(..)"
                , "Diagonal(..)"
                ]
      l3exps  = l2exps ++ [ "Side(..)" ]
  --
  mkC2HS "Level1" (docs 1) l1exps funsL1
  mkC2HS "Level2" (docs 2) l2exps funsL2

mkC2HS :: String -> [String] -> [String] -> [FunGroup] -> IO ()
mkC2HS mdl docs exps funs =
  let exts    = [ "CPP"
                , "ForeignFunctionInterface"
                ]
      name    = [ "Foreign", "CUDA", "BLAS", mdl ]
      path    = intercalate "/" name ++ ".chs"
      imps    = [ "Data.Complex"
                , "Foreign"
                , "Foreign.Storable.Complex ()"
                , "Foreign.CUDA.Ptr"
                , "Foreign.CUDA.BLAS.Internal.C2HS"
                , "Foreign.CUDA.BLAS.Internal.Types"
                ]
      fis     = funInsts Unsafe funs
      exps'   = exps ++ map cfName fis
      body    = "#include \"cbits/stubs.h\""
              : "{# context lib=\"cublas\" #}"
              : ""
              : "{-# INLINE useDevP #-}"
              : "useDevP :: DevicePtr a -> Ptr b"
              : "useDevP = useDevicePtr . castDevPtr"
              : ""
              : map mkFun fis
  in
  writeFile path $ mkModule exts name docs exps' imps body


mkModule
    :: [String]       -- ^ extensions
    -> [String]       -- ^ module name segments
    -> [String]       -- ^ module documentation
    -> [String]       -- ^ exports
    -> [String]       -- ^ imports
    -> [String]       -- ^ module contents
    -> String
mkModule exts name docs exps imps body =
  unlines
    $ "--"
    : "-- This module is auto-generated. Do not edit directly."
    : "--"
    : ""
    : map (printf "{-# LANGUAGE %s #-}") exts
   ++ "-- |"
    :("-- Module      : " ++ intercalate "." name)
    : "-- Copyright   : [2017] Trevor L. McDonell"
    : "-- License     : BSD3"
    : "--"
    : "-- Maintainer  : Trevor L. McDonell <tmcdonell@cse.unsw.edu.au>"
    : "-- Stability   : experimental"
    : "-- Portability : non-portable (GHC extensions)"
    : "--"
    : map (\x -> if null x then "--" else "-- " ++ x) docs
   ++ ""
    : printf "module %s (\n" (intercalate "." name)
    : map (printf "  %s,") exps
   ++ printf "\n) where"
    : ""
    : map (printf "import %s") imps
   ++ ""
    : body


-- | Generates a c2hs hook for the function.
--
mkFun :: CFun -> String
mkFun (CFun safe name params ret doc) =
  intercalate "\n"
    [ if null doc then "" else "-- | " <> doc
    , printf "{-# INLINEABLE %s #-}" name
    , printf "{# fun%s %s%s { %s } -> %s #}" safe' cName hName params' ret'
    ]
  where
    cName   = funMangler name
    hName   = if name == cName then "" else " as " <> name
    safe'   = if safe then "" else " unsafe"
    params' = intercalate ", " $ fmap (mkParamType . convType) params
    ret'    = mkRetType $ convType ret

data Safety
  = Safe
  | Unsafe
  deriving (Bounded, Enum, Eq, Ord, Read, Show)

-- | Represents a C type.
--
data Type
  = THandle
  | TStatus
  | TVoid
  | TPtr (Maybe AddrSpace) Type
  | TInt
  | TFloat
  | TDouble
  | TComplex Type
  | TEnum String
  | TDummy Int                    -- ^ Used for extracting the bound variables
  deriving (Eq, Show)

data AddrSpace
  = Host | Device
  deriving (Eq, Show)

realTypes :: [Type]
realTypes = [ float, double ]

complexTypes :: [Type]
complexTypes = complex <$> realTypes

floatingTypes :: [Type]
floatingTypes = realTypes <> complexTypes

floatingTypesB :: [(Type, Type)]
floatingTypesB = do
  t <- floatingTypes
  return $ case t of
    TComplex t' -> (t', t)
    _           -> (t,  t)

floatingTypesE :: [(Type, Type)]
floatingTypesE = do
  t <- floatingTypes
  case t of
    TComplex t' -> [(t, t), (t, t')]
    _           -> [(t, t)]

-- | Represents a C function.
--
data Fun
  = Fun
    { fName  :: String
    , fTypes :: [Type]
    , _fDoc  :: String
    }

-- | Construct a 'Fun'.
--
fun :: String -> [Type] -> Fun
fun name types = Fun name types ""

-- | Represents a marshallable C type for c2hs.
--
data HType = HType
             String                     -- in marshaller
             String                     -- type
             String                     -- out marshaller
             deriving Show

mkParamType :: HType -> String
mkParamType (HType m s _) =
  if null m then s' else m <> " " <> s'
  where s' = "`" <> s <> "'"

mkRetType :: HType -> String
mkRetType (HType _ s m) =
  if null m then s' else s' <> " " <> m
  where s' = "`" <> s <> "'"

-- | Represents a C function hook for c2hs.
--
data CFun
  = CFun
    { cfSafe    :: Bool
    , cfName    :: String
    , _cfParams :: [Type]
    , _cfRet    :: Type
    , cfDoc     :: String
    }

-- | Construct a 'CFun'.
--
cFun :: String -> [Type] -> Type -> CFun
cFun name params ret = CFun True name params ret ""

-- unreturnable :: Type -> Bool
-- unreturnable t = case t of
--   TComplex TFloat  -> True
--   TComplex TDouble -> True
--   _                -> False

substitute :: String -> String -> String
substitute s y = case y of
  []     -> []
  x : xs ->
    let xs' = substitute s xs in
    case x of
      '?' -> s <> xs'
      _   -> x : xs'

typeAbbrev :: Type -> String
typeAbbrev t = case t of
  TFloat           -> "s"
  TDouble          -> "d"
  TComplex TFloat  -> "c"
  TComplex TDouble -> "z"
  _                -> error ("no valid abbreviation for: " <> show t)

decorate :: [Type] -> String -> String
decorate [a]                = substitute $ typeAbbrev a
decorate [a, b] | a == b    = substitute $ typeAbbrev a
                | otherwise = substitute $ typeAbbrev a <> typeAbbrev b
decorate _                  = error "decorate: bad args"

-- NOTE: Here we assume that both the C and Haskell types have identical
-- representations; this isn't in the specs but in practice the Storable
-- instances are identical so it should work fine
--
convType :: Type -> HType
convType t = case t of
  TVoid             -> simple "()"
  TInt              -> simple "Int"
  TEnum t'          -> enum t'
  TFloat            -> floating "Float"
  TDouble           -> floating "Double"
  -- TComplex t'       -> case t' of
  --   TFloat  -> complex_ "Complex Float"
  --   TDouble -> complex_ "Complex Double"
  --   _       -> error $ "can not marshal type type: " <> show t
  TPtr as t'        -> pointer as $ case t' of
    TInt              -> "Int"
    TFloat            -> "Float"
    TDouble           -> "Double"
    TComplex TFloat   -> "(Complex Float)"
    TComplex TDouble  -> "(Complex Double)"
    _                 -> error $ "can not marshal type: " <> show t
  THandle           -> HType "useHandle" "Handle" ""
  TStatus           -> HType "" "()" "checkStatus*"
  _                 -> error $ "unmarshallable type: " <> show t
  where
    simple s    = HType "" s ""
    enum s      = HType "cFromEnum" s "cToEnum"
    floating s  = HType ("C" <> s) s ("fromC" <> s)
    -- complex_ s  = HType "withVoidPtr*" s ""
    --
    pointer Nothing s       = HType "castPtr"  ("Ptr " <> s) ""
    pointer (Just Host) s   = HType "useHostP" ("HostPtr " <> s) ""
    pointer (Just Device) s = HType "useDevP"  ("DevicePtr " <> s) ""


-- shortcuts

void :: Type
void = TVoid

ptr :: Type -> Type
ptr = TPtr Nothing

dptr :: Type -> Type
dptr = TPtr (Just Device)

hptr :: Type -> Type
hptr = TPtr (Just Host)

int :: Type
int = TInt

float :: Type
float = TFloat

double :: Type
double = TDouble

complex :: Type -> Type
complex = TComplex

index :: Type
index = TInt

transpose :: Type
transpose = TEnum "Operation"

uplo :: Type
uplo = TEnum "Fill"

diag :: Type
diag = TEnum "Diagonal"

side :: Type
side = TEnum "Side"

funInsts :: Safety -> [FunGroup] -> [CFun]
funInsts safety funs = mangleFun safety <$> concatFunInstances funs

-- | cuBLAS function signatures. The initial context handle argument is added
-- implicitly.
--
-- Level 1 (vector-vector) operations.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublas-level-1-function-reference>
--
funsL1 :: [FunGroup]
funsL1 =
  [ gpA $ \ a   -> fun "i?amax" [ int, dptr a, int, ptr int ]
  , gpA $ \ a   -> fun "i?amin" [ int, dptr a, int, ptr int ]
  , gpB $ \ a b -> fun "?asum"  [ int, dptr b, int, ptr a ]
  , gpA $ \ a   -> fun "?axpy"  [ int, ptr a, dptr a, int, dptr a, int ]
  , gpA $ \ a   -> fun "?copy"  [ int, dptr a, int, dptr a, int ]
  , gpR $ \ a   -> fun "?dot"   [ int, dptr a, int, dptr a, int, ptr a ]
  , gpC $ \ a   -> fun "?dotu"  [ int, dptr a, int, dptr a, int, ptr a ]
  , gpC $ \ a   -> fun "?dotc"  [ int, dptr a, int, dptr a, int, ptr a ]
  , gpB $ \ a b -> fun "?nrm2"  [ int, dptr b, int, ptr a ]
  , gpE $ \ a b -> fun "?rot"   [ int, dptr a, int, dptr a, int, ptr b, ptr b ]
  , gpA $ \ a   -> fun "?rotg"  [ ptr a, ptr a, ptr a, ptr a ]
  , gpR $ \ a   -> fun "?rotm"  [ int, dptr a, int, dptr a, int, ptr a ]
  , gpR $ \ a   -> fun "?rotmg" [ ptr a, ptr a, ptr a, ptr a, ptr a ]
  , gpE $ \ a b -> fun "?scal"  [ int, ptr b, dptr a, int ]
  , gpA $ \ a   -> fun "?swap"  [ int, dptr a, int, dptr a, int ]
  ]

-- Level 2 (matrix-vector) operations.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublas-level-2-function-reference>
--
funsL2 :: [FunGroup]
funsL2 =
  [ gpA $ \ a   -> fun "?gbmv"  [ transpose, int, int, int, int, ptr a
                                , dptr a, int, dptr a, int, ptr a, dptr a, int ]
  , gpA $ \ a   -> fun "?gemv"  [ transpose, int, int, ptr a, dptr a
                                , int, dptr a, int, ptr a, dptr a, int ]
  , gpR $ \ a   -> fun "?ger"   [ int, int, ptr a, dptr a, int, dptr a
                                , int, dptr a, int ]
  , gpC $ \ a   -> fun "?gerc"  [ int, int, ptr a, dptr a, int
                                , dptr a, int, dptr a, int ]
  , gpC $ \ a   -> fun "?geru"  [ int, int, ptr a, dptr a, int
                                , dptr a, int, dptr a, int ]
  , gpR $ \ a   -> fun "?sbmv"  [ uplo, int, int, ptr a, dptr a, int, dptr a
                                , int, ptr a, dptr a, int ]
  , gpR $ \ a   -> fun "?spmv"  [ uplo, int, ptr a, dptr a, dptr a, int, ptr a
                                , dptr a, int ]
  , gpR $ \ a   -> fun "?spr"   [ uplo, int, ptr a, dptr a
                                , int, dptr a ]
  , gpR $ \ a   -> fun "?spr2"  [ uplo, int, ptr a, dptr a, int, dptr a
                                , int, dptr a ]
  , gpA $ \ a   -> fun "?symv"  [ uplo, int, ptr a, dptr a, int, dptr a, int
                                , ptr a, dptr a, int ]
  , gpA $ \ a   -> fun "?syr"   [ uplo, int, ptr a, dptr a, int, dptr a
                                , int ]
  , gpA $ \ a   -> fun "?syr2"  [ uplo, int, ptr a, dptr a, int, dptr a
                                , int, dptr a, int ]
  , gpA $ \ a   -> fun "?tbmv"  [ uplo, transpose, diag, int, int
                                , dptr a, int, dptr a, int ]
  , gpA $ \ a   -> fun "?tbsv"  [ uplo, transpose, diag, int, int
                                , dptr a, int, dptr a, int ]
  , gpA $ \ a   -> fun "?tpmv"  [ uplo, transpose, diag, int
                                , dptr a, dptr a, int ]
  , gpA $ \ a   -> fun "?tpsv"  [ uplo, transpose, diag, int
                                , dptr a, dptr a, int ]
  , gpA $ \ a   -> fun "?trmv"  [ uplo, transpose, diag, int
                                , dptr a, int, dptr a, int ]
  , gpA $ \ a   -> fun "?trsv"  [ uplo, transpose, diag, int
                                , dptr a, int, dptr a, int ]
  , gpC $ \ a   -> fun "?hemv"  [ uplo, int, ptr a, dptr a, int, dptr a
                                , int, ptr a, dptr a, int ]
  , gpC $ \ a   -> fun "?hbmv"  [ uplo, int, int, ptr a, dptr a
                                , int, dptr a, int, ptr a, dptr a, int ]
  , gpC $ \ a   -> fun "?hpmv"  [ uplo, int, ptr a, dptr a, dptr a
                                , int, ptr a, dptr a, int ]
  , gpQ $ \ a   -> fun "?her"   [ uplo, int, ptr a, dptr (complex a), int
                                , dptr (complex a), int ]
  , gpC $ \ a   -> fun "?her2"  [ uplo, int, ptr a, dptr a, int
                                , dptr a, int, dptr a, int ]
  , gpQ $ \ a   -> fun "?hpr"   [ uplo, int, ptr a, dptr (complex a), int
                                , dptr (complex a) ]
  , gpC $ \ a   -> fun "?hpr2"  [ uplo, int, ptr a, dptr a, int
                                , dptr a, int, dptr a ]
  ]

  -- , gpA $ \ a   -> fun "?gemm"  [ order, transpose, transpose, int, int, int, a
  --                               , ptr a, int, ptr a, int, a, ptr a, int, void ]
  -- , gpA $ \ a   -> fun "?symm"  [ order, side, uplo, int, int, a, ptr a, int
  --                               , ptr a, int, a, ptr a, int, void ]
  -- , gpA $ \ a   -> fun "?syrk"  [ order, uplo, transpose, int, int, a, ptr a
  --                               , int, a, ptr a, int, void ]
  -- , gpA $ \ a   -> fun "?syr2k" [ order, uplo, transpose, int, int, a, ptr a
  --                               , int, ptr a, int, a, ptr a, int, void ]
  -- , gpC $ \ a   -> fun "?hemm"  [ order, side, uplo, int, int, a, ptr a, int
  --                               , ptr a, int, a, ptr a, int, void ]
  -- , gpQ $ \ a   -> fun "?herk"  [ order, uplo, transpose, int, int, a
  --                               , ptr (complex a), int, a
  --                               , ptr (complex a), int, void ]
  -- , gpQ $ \ a   -> fun "?her2k" [ order, uplo, transpose, int, int, complex a
  --                               , ptr (complex a), int, ptr (complex a)
  --                               , int, a, ptr (complex a), int, void ]
  -- , gpA $ \ a   -> fun "?trmm"  [ order, side, uplo, transpose, diag, int, int
  --                               , a, ptr a, int, ptr a, int, void ]
  -- , gpA $ \ a   -> fun "?trsm"  [ order, side, uplo, transpose, diag, int, int
  --                               , a, ptr a, int, ptr a, int, void ]
  -- ]

data FunGroup
  = FunGroup
    { _gpName :: String
    , _gpType :: [Type]
    , gpInsts :: [FunInstance]
    }

gp :: Fun -> FunGroup
gp f = FunGroup (fName f) (fTypes f) [FunInstance [] f]

-- | Function group over @s d c z@.
gpA :: (Type -> Fun) -> FunGroup
gpA = makeFunGroup1 decorate floatingTypes

-- | Function group over @s d@.
gpR :: (Type -> Fun) -> FunGroup
gpR = makeFunGroup1 decorate realTypes

-- | Function group over @s d@ but relabel them as @c z@.
gpQ :: (Type -> Fun) -> FunGroup
gpQ = makeFunGroup1 (decorate . (complex <$>)) realTypes

-- | Function group over @c z@.
gpC :: (Type -> Fun) -> FunGroup
gpC = makeFunGroup1 decorate complexTypes

-- | Function group over @ss dd sc dz@.
gpB :: (Type -> Type -> Fun) -> FunGroup
gpB = makeFunGroup2 decorate floatingTypesB

-- | Function group over @ss dd cc zz cs zd@.
gpE :: (Type -> Type -> Fun) -> FunGroup
gpE = makeFunGroup2 decorate floatingTypesE

makeFunGroup1 :: ([Type] -> String -> String)
              -> [Type]
              -> (Type -> Fun)
              -> FunGroup
makeFunGroup1 d ts ff = makeFunGroup 1 d ts' ff'
  where ts'      = [ [a] | a <- ts ]
        ff' args = ff a   where [a]    = args

makeFunGroup2 :: ([Type] -> String -> String)
              -> [(Type, Type)]
              -> (Type -> Type -> Fun)
              -> FunGroup
makeFunGroup2 d ts ff = makeFunGroup 2 d ts' ff'
  where ts'      = [ [a, b] | (a, b) <- ts ]
        ff' args = ff a b where [a, b] = args

makeFunGroup :: Int
             -> ([Type] -> String -> String)
             -> [[Type]]
             -> ([Type] -> Fun)
             -> FunGroup
makeFunGroup n decorator ts ff =
  let f = ff (take n (TDummy <$> [0 ..])) in
  FunGroup (substitute "" $ fName f) (fTypes f) $ do
    t <- ts
    let f' = ff t
    return $ FunInstance t (f' { fName = decorator t $ fName f'})

data FunInstance
  = FunInstance
    { _fiArgs :: [Type]
    , fiFun   :: Fun
    }

concatFunInstances :: [FunGroup] -> [Fun]
concatFunInstances = (>>= (>>= return . fiFun) . gpInsts)

funMangler :: String -> String
funMangler []     = error "funMangler: empty input"
funMangler (x:xs) = printf "cublas%c%s_v2" (toUpper x) xs

mangleFun :: Safety -> Fun -> CFun
mangleFun safety (Fun name params doc) =
  CFun (safety==Safe) name (THandle : params) TStatus doc

