#!/bin/bash -l
#SBATCH --job-name=predsim_install
#SBATCH --partition=general
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err



module load gcc/12.3.0
module load cmake/3.26.3-gcccore-12.3.0
module load openblas/0.3.23-gcc-12.3.0
module load matlab/R2023b5
module load java/21.0.8
module load pcre2/10.42-gcccore-12.3.0
module load python/3.11.3-gcccore-12.3.0


export CFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"
export CXXFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"





cd $HOME
mkdir -p $HOME/deps
# create the python venv and activate it
python -m venv "$HOME/deps/python${EBVERSIONPYTHON}-GCCcore-${EBVERSIONGCCCORE}"
source $HOME/deps/python3.11.3-GCCcore-12.3.0/bin/activate


mkdir -p $HOME/predsim_install/coinbrew
cd $HOME/predsim_install/coinbrew
wget https://raw.githubusercontent.com/coin-or/coinbrew/master/coinbrew

# Locate OpenBLAS lib dir (lib64 vs lib) 
if [ -f "$EBROOTOPENBLAS/lib64/libopenblas.so" ]; then
	export OBLIBDIR="$EBROOTOPENBLAS/lib64" 
else
     	export OBLIBDIR="$EBROOTOPENBLAS/lib" 
fi
export OBLAS="$OBLIBDIR/libopenblas.so"


# Create local wrappers so -llapack and -lblas resolve to OpenBLAS
mkdir -p "$HOME/lib/blaswrap"
ln -sf "$OBLIBDIR/libopenblas.so" "$HOME/lib/blaswrap/liblapack.so"
ln -sf "$OBLIBDIR/libopenblas.so" "$HOME/lib/blaswrap/libblas.so"


# Strong link hints for Autotools-based ThirdParty/Mumps
export LDFLAGS="-L$HOME/lib/blaswrap -L$OBLIBDIR ${LDFLAGS:-}"
export LIBS="-llapack -lblas ${LIBS:-}"
export BLAS_LIBS="-L$HOME/lib/blaswrap -lblas"
export LAPACK_LIBS="-L$HOME/lib/blaswrap -llapack"

cd "$HOME/predsim_install/coinbrew"
chmod +x coinbrew
./coinbrew build Ipopt \
  --prefix="$HOME/deps/ipopt" \
  --no-prompt \
  --tests=none \
  --verbosity=2 \
  --enable-shared \
  --reconfigure
mkdir -p $HOME/predsim_install/swig
cd $HOME/predsim_install/swig

wget -O swig-4.1.1.tar.gz https://prdownloads.sourceforge.net/swig/swig-4.1.1.tar.gz
tar xzf swig-4.1.1.tar.gz
cd swig-4.1.1
./configure --prefix=$HOME/deps/swig-4.1.1 --with-pcre #--without-pcre
make -j4
make install

# Expose to this shell session
export PATH="$HOME/deps/swig-4.1.1/bin:$PATH"
export SWIG_DIR="$HOME/deps/swig-4.1.1/share/swig/4.1.1"
cd $HOME


mkdir -p $HOME/predsim_install/spdlog
cd $HOME/predsim_install/spdlog
wget -O spdlog-1.15.3.tar.gz https://github.com/gabime/spdlog/archive/refs/tags/v1.15.3.tar.gz
tar xzf spdlog-1.15.3.tar.gz
cd spdlog-1.15.3
rm -rf build && mkdir build && cd build
# Build shared lib, using the BUNDLED fmt (SPDLOG_FMT_EXTERNAL=OFF by default)
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/deps/spdlog" \
  -DSPDLOG_BUILD_SHARED=ON \
  -DSPDLOG_FMT_EXTERNAL=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON

cmake --build . --parallel 4 
cmake --install .

#### CASADI INSTALL
export LD_LIBRARY_PATH=$HOME/deps/ipopt/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=$HOME/deps/ipopt/lib/pkgconfig:$PKG_CONFIG_PATH

cd $HOME/predsim_install

git clone --branch 3.7.1 --depth 1 git@github.com:indialindemann/casadi_private.git
cd $HOME/predsim_install/casadi_private
rm -rf $HOME/predsim_install/casadi_private/build
mkdir $HOME/predsim_install/casadi_private/build
cd $HOME/predsim_install/casadi_private/build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/local/casadi \
  \
  -DWITH_IPOPT=ON \
  -DWITH_BUILD_IPOPT=OFF \
  -DIPOPT_ROOT_DIR=$HOME/deps/ipopt \
  \
  -DWITH_MUMPS=OFF \
  -DWITH_BUILD_MUMPS=OFF \
  \
  -DWITH_LAPACK=ON \
  -DWITH_BUILD_LAPACK=OFF \
  -DWITH_OPENBLAS=ON \
  \
  -DWITH_PYTHON=ON \
  -DWITH_PYTHON_GIL_RELEASE=ON \
  \
  -DSWIG_EXECUTABLE=$HOME/deps/swig-4.1.1/bin/swig \
  -DSWIG_DIR=$HOME/deps/swig-4.1.1/share/swig/4.1.1 \
  \
  -DWITH_THREAD=ON \
  -DWITH_COMMON=OFF \
  -DWITH_EXAMPLES=OFF \
  -DWITH_DOCUMENTATION=OFF \
  \
  -DPython_EXECUTABLE=$HOME/deps/python3.11.3-GCCcore-12.3.0/bin/python \
  -DPython3_EXECUTABLE=$HOME/deps/python3.11.3-GCCcore-12.3.0/bin/python \
  -DCMAKE_INSTALL_PYTHONDIR=$HOME/deps/python3.11.3-GCCcore-12.3.0/lib/python3.11/site-packages
  \
cmake --build . --parallel 4
make install

# cmake workaround for cassadi python package
mkdir -p $HOME/casadi_private/build/lib/casadi
mv $HOME/casadi_private/build/lib/_casadi.so \
   $HOME/casadi_private/build/lib/casadi/
cp $HOME/casadi_private/build/swig/python/casadi.py \
   $HOME/casadi_private/build/lib/casadi/
cat > $HOME/casadi_private/build/lib/casadi/__init__.py <<'EOF'
from .casadi import *
__version__ = "3.7.1_cmake_fix"
EOF
export PYTHONPATH=$HOME/casadi_private/build/lib:$PYTHONPATH
export LD_LIBRARY_PATH=$HOME/casadi_private/build/lib:$LD_LIBRARY_PATH


cd $HOME/predsim_install
git clone https://github.com/simbody/simbody.git simbody --depth 1
SIMBODY_SRC="${SIMBODY_SRC:-$HOME/predsim_install/simbody}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/deps/simbody}"
BUILD_DIR="${BUILD_DIR:-$SIMBODY_SRC/build}"
mkdir -p "$BUILD_DIR"
# Try to locate OpenBLAS lib (lib or lib64 on different sites)
BLAS_LIB=""
if [[ -n "${EBROOTOPENBLAS:-}" ]]; then
  if [[ -f "$EBROOTOPENBLAS/lib64/libopenblas.so" ]]; then
    BLAS_LIB="$EBROOTOPENBLAS/lib64/libopenblas.so"
  elif [[ -f "$EBROOTOPENBLAS/lib/libopenblas.so" ]]; then
    BLAS_LIB="$EBROOTOPENBLAS/lib/libopenblas.so"
  fi
fi
cmake -S "$SIMBODY_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DSIMBODY_USE_OPENMP=ON \
  ${BLAS_LIB:+-DBLAS_LIBRARIES="$BLAS_LIB"} \
  ${BLAS_LIB:+-DLAPACK_LIBRARIES="$BLAS_LIB"}

cmake --build "$BUILD_DIR" --parallel 4
cmake --install "$BUILD_DIR"
cd $HOME/predsim_install

git clone https://github.com/opensim-org/opensim-core.git --depth 1
cd opensim-core
mkdir build
cd build
export SIMBODY_HOME="$HOME/deps/simbody"
export PKG_CONFIG_PATH="$HOME/deps/ipopt/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$HOME/deps/simbody/lib:$HOME/deps/ipopt/lib:$HOME/deps/spdlog/lib:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$HOME/deps/spdlog:$HOME/deps/simbody:$HOME/deps/ipopt:${CMAKE_PREFIX_PATH:-}"
export CMAKE_FIND_PACKAGE_PREFER_CONFIG=TRUE
export CMAKE_FIND_USE_PACKAGE_REGISTRY=OFF
export CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/deps/opensim-install" \
  -DBUILD_JAVA_WRAPPING=ON \
  -DBUILD_PYTHON_WRAPPING=OFF \
  -DBUILD_TESTING=OFF \
  -DSUPERLU=OFF \
  -DSIMBODY_HOME="$SIMBODY_HOME" \
  -DCMAKE_PREFIX_PATH="$HOME/deps/spdlog;$HOME/deps/simbody;$HOME/deps/ipopt" \
  -DBLA_VENDOR=OpenBLAS \
  -DBLAS_LIBRARIES="$OBLAS" \
  -DLAPACK_LIBRARIES="$OBLAS" \
  -DOPENSIM_WITH_CASADI=OFF
cmake --build . --parallel 4
cmake --install .

# Create the expected directories under your install prefix
mkdir -p "$HOME/deps/opensim-install/sdk/Java"
mkdir -p "$HOME/deps/opensim-install/sdk/lib"

# Copy the JAR and JNI .so from the build tree
cp -v "$HOME/predsim_install/opensim-core/build/Bindings/Java/src/org-opensim-modeling.jar" \
      "$HOME/deps/opensim-install/sdk/Java/"

cp -v "$HOME/predsim_install/opensim-core/build/libosimJavaJNI.so" \
      "$HOME/deps/opensim-install/sdk/lib/"

export LD_LIBRARY_PATH="$HOME/opensim-install/sdk/lib:$HOME/opensim-install/lib:$HOME/deps/simbody/lib:$HOME/deps/ipopt/lib:${LD_LIBRARY_PATH:-}"

cd $HOME/predsim_install
mkdir -p opensim_win
cd opensim_win
echo "Manual download time: See instructions"

# Installing / cloneing predsim
# Note if branches change / are merged the cloned branch may need to be changed
cd $HOME
git clone --recurse-submodules -b cleancurvev4 git@github.com:indialindemann/PredSim.git


# 1) Create the MATLAB preferences folder for R2023b (if it doesn't exist)
mkdir -p $HOME/.matlab/R2023b
# 2) Tell MATLAB where to find the JNI .so files (OpenSim, Simbody, Ipopt)
echo  "$HOME/deps/simbody/lib" >> $HOME/.matlab/R2023b/javalibrarypath.txt
echo  "$HOME/deps/ipopt/lib" >> $HOME/.matlab/R2023b/javalibrarypath.txt
echo  "$HOME/deps/opensim-install/lib" >> $HOME/.matlab/R2023b/javalibrarypath.txt
echo  "$HOME/deps/opensim-install/sdk/lib" >> $HOME/.matlab/R2023b/javalibrarypath.txt
echo "$EBROOTOPENBLAS/lib64" >> $HOME/.matlab/R2023b/javalibrarypath.txt


