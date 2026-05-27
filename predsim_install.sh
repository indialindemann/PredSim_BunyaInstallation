#!/bin/bash -l
#SBATCH --job-name=predsim_install
#SBATCH --partition=general
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err


# There will likely need to be soe switching code here but for now hardcoding the ubuntu modules
# or rather enough to catch the version
module load gcc/12.3.0
module load cmake/3.26
module load openblas/0.3.23-gcc-12.3.0
module load matlab/
module load java/
module load python/3.11


#TODO SWITCHING BASED ON BUNYA OR HOME (OR SOME OTHER THING IN WHCIH CASE DO NOTHING)
#export CFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"
#export CXXFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"

#export CFLAGS="-O2 -march=native -mtune=native -fPIC"
#export CXXFLAGS="-O2 -march=native -mtune=native -fPIC"
#export FFLAGS="-O2 -march=native -mtune=native -fPIC"



cd $HOME
mkdir -p $HOME/deps
#####################
### PYTHON ENVIRONMENT
#####################
# create the python venv and activate it
#python -m venv "$HOME/deps/python${EBVERSIONPYTHON}-GCCcore-${EBVERSIONGCCCORE}"
#source $HOME/deps/python3.11.3-GCCcore-12.3.0/bin/activate


# TODO this needs to be validated on bunya
PYVER=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')
VENV="$HOME/deps/python-${PYVER}"

if [ ! -d "$VENV" ]; then
    python -m venv "$VENV"
fi

source "$VENV/bin/activate"

##########################
### IPOPT/COINBREW INSTALL
##########################
mkdir -p $HOME/predsim_install/coinbrew
cd $HOME/predsim_install/coinbrew
wget https://raw.githubusercontent.com/coin-or/coinbrew/master/coinbrew

## Locate OpenBLAS lib dir (lib64 vs lib) 
#if [ -f "$EBROOTOPENBLAS/lib64/libopenblas.so" ]; then
#	export OBLIBDIR="$EBROOTOPENBLAS/lib64" 
#else
#     	export OBLIBDIR="$EBROOTOPENBLAS/lib" 
#fi
#export OBLAS="$OBLIBDIR/libopenblas.so"

## UBUNTU VERSION
export OPENBLAS_ROOT=$(spack location -i openblas)
if [ -f "$OPENBLAS_ROOT/lib64/libopenblas.so" ]; then
    export OBLIBDIR="$OPENBLAS_ROOT/lib64"
elif [ -f "$OPENBLAS_ROOT/lib/libopenblas.so" ]; then
    export OBLIBDIR="$OPENBLAS_ROOT/lib"
else
    echo "ERROR: libopenblas.so not found under $OPENBLAS_ROOT"
    exit 1
fi

export OBLAS="$OBLIBDIR/libopenblas.so"

echo "OPENBLAS_ROOT=$OPENBLAS_ROOT"
echo "OBLIBDIR=$OBLIBDIR"
echo "OBLAS=$OBLAS"



# Create local wrappers so -llapack and -lblas resolve to OpenBLAS
mkdir -p "$HOME/lib/blaswrap"
ln -sf "$OBLIBDIR/libopenblas.so" "$HOME/lib/blaswrap/liblapack.so"
ln -sf "$OBLIBDIR/libopenblas.so" "$HOME/lib/blaswrap/libblas.so"


# Strong link hints for Autotools-based ThirdParty/Mumps
export LDFLAGS="-L$HOME/lib/blaswrap -L$OBLIBDIR ${LDFLAGS:-}"
export LIBS="-llapack -lblas ${LIBS:-}"
export BLAS_LIBS="-L$HOME/lib/blaswrap -lblas"
export LAPACK_LIBS="-L$HOME/lib/blaswrap -llapack"

# ubuntu specific line
export LD_LIBRARY_PATH="$OBLIBDIR:${LD_LIBRARY_PATH:-}"


cd "$HOME/predsim_install/coinbrew"
chmod +x coinbrew
./coinbrew build Ipopt \
  --prefix="$HOME/deps/ipopt" \
  --no-prompt \
  --tests=none \
  --verbosity=2 \
  --enable-shared \
  --reconfigure


###################
# SWIG INSTALLATION
###################


mkdir -p $HOME/predsim_install/swig
cd $HOME/predsim_install/swig


# Old /actual/ swig program
export SWIG_VERSION="swig-4.1.1"
wget -O swig-4.1.1.tar.gz https://prdownloads.sourceforge.net/swig/swig-4.1.1.tar.gz
tar xzf swig-4.1.1.tar.gz
cd swig-4.1.1
./configure --prefix=$HOME/deps/swig-4.1.1 --with-pcre #--without-pcre

# new and improved 24 year old fork
export SWIG_VERSION="swig-3.0.11"
export SWIG_CASADI_BRANCH="matlab-customdoc"  # this version is referenced in the actual casadi docs (https://github.com/casadi/casadi/wiki/matlab#installation-instructions)
#export SWIG_VERSION="swig-4.4.0" # I just manually looked this up from the install output of the below fork
#export SWIG_CASADI_BRANCH="matlab-customdoc2"  # this is more up to date and appears merged with the latest(ish) swig version (https://github.com/jaeandersson/swig/tree/matlab-customdoc2)

echo "Removing existing swig"
rm -rf swig

git clone --branch "$SWIG_CASADI_BRANCH" --depth 1 https://github.com/jaeandersson/swig.git
cd swig
wget -O pcre-8.45.tar.bz2 \
  https://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.bz2

export GCC7="$(spack location -i gcc@7.5.0)/bin"

CC=$GCC7/gcc CXX=$GCC7/g++ ./autogen.sh
CC=$GCC7/gcc CXX=$GCC7/g++ Tools/pcre-build.sh
CC=$GCC7/gcc CXX=$GCC7/g++ ./configure --prefix=$HOME/deps/$SWIG_VERSION --with-pcre

CC=$GCC7/gcc CXX=$GCC7/g++ make -j4
CC=$GCC7/gcc CXX=$GCC7/g++ make install

# Expose to this shell session
export PATH="$HOME/deps/$SWIG_VERSION/bin:$PATH"
export SWIG_DIR="$HOME/deps/$SWIG_VERSION/share/swig/3.0.11"  # version number is hard coded atm, you will need to change if messing with the swig version

cd $HOME

######################
# SPDLOG INSTALLATION
######################


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



##################
#### CASADI INSTALL
###################
# Assumes the correct Python venv is already activated

#### PYTHON DEPS FOR CASADI
python -m pip install --upgrade pip setuptools wheel
python -m pip install numpy scipy

export LD_LIBRARY_PATH="$HOME/deps/ipopt/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$HOME/deps/ipopt/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

CASADI_VERSION="3.7.1"
CASADI_INSTALL="$HOME/deps/casadi"
PYTHON_EXEC="$(which python)"
PYTHON_SITE="$(python -c 'import site; print(site.getsitepackages()[0])')"

cd "$HOME/predsim_install"
rm -rf "$HOME/predsim_install/casadi_private"
git clone --branch "$CASADI_VERSION" --depth 1 git@github.com:indialindemann/casadi_private.git

cd "$HOME/predsim_install/casadi_private"

rm -rf build
mkdir build
cd build


# DWITH_MATLAB ->  See https://github.com/casadi/casadi/wiki/matlab
# DWITH_DEEPBIND_ON -> # See https://github.com/casadi/casadi/wiki/matlab#installation-instructions Step 6
# dropped vars
#   #-DWITH_PYTHON_GIL_RELEASE=ON \
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$CASADI_INSTALL" \
  -DPYTHON_PREFIX="$CASADI_INSTALL" \
  \
  -DWITH_IPOPT=ON \
  -DWITH_BUILD_IPOPT=OFF \
  -DIPOPT_ROOT_DIR="$HOME/deps/ipopt" \
  \
  -DWITH_MUMPS=OFF \
  -DWITH_BUILD_MUMPS=OFF \
  \
  -DWITH_LAPACK=ON \
  -DWITH_BUILD_LAPACK=OFF \
  -DWITH_OPENBLAS=ON \
  \
  -DWITH_PYTHON=ON \
  -DWITH_PYTHON3=ON\
  \
  -DWITH_MATLAB=ON\
  -DWITH_DEEPBIND=ON\
  \
  -DSWIG_EXECUTABLE="$HOME/deps/$SWIG_VERSION/bin/swig" \
  -DSWIG_DIR="$SWIG_DIR" \
  \
  -DWITH_THREAD=ON \
  -DWITH_COMMON=OFF \
  -DWITH_EXAMPLES=OFF \
  -DWITH_DOCUMENTATION=OFF \
  \
  -DPython_EXECUTABLE="$PYTHON_EXEC" \
  -DPython3_EXECUTABLE="$PYTHON_EXEC"

cmake --build . --parallel 4
cmake --install .

# Link the CasADi install directory into the active venv
echo "$CASADI_INSTALL" > "$PYTHON_SITE/casadi-local.pth"

# Make shared libraries visible for this shell/job
export LD_LIBRARY_PATH="$CASADI_INSTALL:$CASADI_INSTALL/lib:$HOME/deps/ipopt/lib:${LD_LIBRARY_PATH:-}"

# Quick test
python -c "import casadi; print(casadi.__version__); print(casadi.__file__)"

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


