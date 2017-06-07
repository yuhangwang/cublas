-- |
-- Module      : Foreign.CUDA.BLAS
-- Copyright   : [2014..2017] Trevor L. McDonell
-- License     : BSD3
--
-- Maintainer  : Trevor L. McDonell <tmcdonell@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Foreign.CUDA.BLAS (

  -- * Control
  module Foreign.CUDA.BLAS.Context,
  module Foreign.CUDA.BLAS.Stream,
  module Foreign.CUDA.BLAS.Error,

  -- * Operations
  module Foreign.CUDA.BLAS.Level1,
  module Foreign.CUDA.BLAS.Level2,

) where

import Foreign.CUDA.BLAS.Context                hiding ( Handle(Handle, useHandle) )
import Foreign.CUDA.BLAS.Error                  hiding ( resultIfOk, nothingIfOk )
import Foreign.CUDA.BLAS.Stream

import Foreign.CUDA.BLAS.Level1
import Foreign.CUDA.BLAS.Level2

