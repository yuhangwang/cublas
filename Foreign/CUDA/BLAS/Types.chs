{-# LANGUAGE CPP                      #-}
{-# LANGUAGE ForeignFunctionInterface #-}
-- |
-- Module      : Foreign.CUDA.BLAS.Types
-- Copyright   : [2014..2017] Trevor L. McDonell
-- License     : BSD3
--
-- Maintainer  : Trevor L. McDonell <tmcdonell@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Foreign.CUDA.BLAS.Types
  where

import Prelude                                            hiding ( Either(..) )

#include "cbits/stubs.h"
{# context lib="cublas" #}


-- | An opaque handle to the cuBLAS library context, which is passed to all
-- library function calls.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublashandle_t>
--
newtype Handle = Handle { useHandle :: {# type cublasHandle_t #}}


-- | Indicates which operation needs to be performed with a dense matrix.
--
--   * @N@: no transpose selected
--   * @T@: transpose operation
--   * @C@: conjugate transpose
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublasoperation_t>
--
{# enum cublasOperation_t as Operation
  { underscoreToCase }
  with prefix="CUBLAS_OP" deriving (Eq, Show) #}


-- | Indicates which part, upper or lower, of a dense matrix was filled and
-- consequently should be used by the function.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublasfillmode_t>
--
{# enum cublasFillMode_t as Fill
  { underscoreToCase }
  with prefix="CUBLAS_FILL_MODE" deriving (Eq, Show) #}


-- | Indicates whether the main diagonal of a dense matrix is unity and
-- consequently should not be be touched or modified by the function.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublasdiagtype_t>
--
{# enum cublasDiagType_t as Diagonal
  { underscoreToCase }
  with prefix="CUBLAS_DIAG" deriving (Eq, Show) #}


-- | Indicates whether the dense matrix is on the lift or right side in the
-- matrix equation solved by a particular function.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublassidemode_t>
--
{# enum cublasSideMode_t as Side
  { underscoreToCase }
  with prefix="CUBLAS_SIDE" deriving (Eq, Show) #}


-- | For functions which take scalar value arguments, determines whether those
-- values are passed by reference on the host or device.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublaspointermode_t>
--
{# enum cublasPointerMode_t as PointerMode
  { underscoreToCase }
  with prefix="CUBLAS_POINTER_MODE" deriving (Eq, Show) #}


-- | Determines whether cuBLAS routines can alternate implementations which make
-- use of atomic instructions.
--
-- <http://docs.nvidia.com/cuda/cublas/index.html#cublasatomicsmode_t>
--
{# enum cublasAtomicsMode_t as AtomicsMode
  { underscoreToCase }
  with prefix="CUBLAS_ATOMICS" deriving (Eq, Show) #}
