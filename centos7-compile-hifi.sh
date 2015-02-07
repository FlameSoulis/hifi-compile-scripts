#!/bin/bash

# Home Directory for HifiUser
HIFIDIR="/usr/local/hifi"
# Last Compile Backup Directory
LASTCOMPILE="$HIFIDIR/last-compile"
# Runtime Directory Location
RUNDIR="$HIFIDIR/run"
# Log Directory
LOGSDIR="$HIFIDIR/logs"
# Source Storage Dir
SRCDIR="/usr/local/src"

## Functions ##
function checkroot {
  [ `whoami` = root ] || { sudo "$0" "$@"; exit $?; }
}

function writecommands {
if [[ ! $(cat ~/.bashrc) =~ "compilehifi" && ! $(cat ~/.bashrc) =~ "runhifi" ]]; then
  echo "Writing Bash Command Aliases"
cat <<EOF >> ~/.bashrc

alias compilehifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-compile-hifi.sh)'
alias runhifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-run-hifi.sh)'

EOF
source ~/.bashrc
fi
}

function checkifrunning {
  # Not used now, but in the future will check if ds/ac is running then offer to restart if so
  # For now we just auto restart.
  [[ $(pidof domain-server) -gt 0 ]] && { HIFIRUNNING=1; }
}

function handlerunhifi {
  if [[ $NEWHIFI -eq 1 || HIFIRUNNING -eq 1 ]]; then
    echo "Restarting your HiFi Stack as user 'hifi'"
    export -f runashifi
    su hifi -c "bash -c runashifi"
    exit 0
  fi
}

function runashifi {
  # Everything here is run as the user hifi
  TIMESTAMP=$(date '+%F')
  HIFIDIR=/usr/local/hifi
  HIFIRUNDIR=$HIFIDIR/run
  HIFILOGDIR=$HIFIDIR/logs
  cd $HIFIRUNDIR
  nohup ./domain-server &>> $HIFILOGDIR/domain-$TIMESTAMP.log&
  nohup ./assignment-client -n 4 &>> $HIFILOGDIR/assignment-$TIMESTAMP.log&
}

function doyum {
  echo "Installing EPEL Repo."
  yum install epel-release -y > /dev/null 2>&1
  echo "Installing compile tools, this may take a while on first run."
  yum groupinstall "development tools" -y > /dev/null 2>&1
  echo "Installing base needed tools, this also may take a while on first run."
  yum install openssl-devel git wget sudo  freeglut* libXmu-* libXi-devel glew glew-devel tbb tbb-devel soxr soxr-devel qt5-qt* -y > /dev/null 2>&1
}

function killrunning {
  kill -9 $(ps aux | grep '[d]omain-server' | awk '{print $2}') > /dev/null 2>&1
  kill -9 $(ps aux | grep '[a]ssignment-client' | awk '{print $2}') > /dev/null 2>&1
  # Flags HIFIRUNNING here since in the future it will be used as a flag to
  # check if it actually was running, this makes it restart on rebuild.
  HIFIRUNNING=1
}

function createuser {
  #HIFIUSER_EXISTS=$(grep -c "^hifi:" /etc/passwd)
  if [[ $(grep -c "^hifi:" /etc/passwd) = "0" ]]; then
    useradd -s /bin/bash -r -m -d $HIFIDIR hifi
    NEWHIFI=1
  fi
}

function removeuser {
  userdel -r hifi > /dev/null 2>&1
}

function changeowner  {
  if [ -d "$HIFIDIR" ]; then
    chown -R hifi:hifi $HIFIDIR
  fi  
}

function setuphifidirs {

  if [[ ! -d $HIFIDIR ]]; then
    echo "Creating $HIFIDIR"
    mkdir $HIFIDIR
    NEWHIFI=1
  fi

  # check if this is a new compile, otherwise move handle that process
  if [[ $NEWHIFI -eq 1 ]]; then
    pushd $HIFIDIR > /dev/null

    if [[ ! -d "$LASTCOMPILE" ]]; then
      echo "Creating Last-Compile Backup Directory"
      mkdir $LASTCOMPILE
    fi

    if [[ ! -d "$RUNDIR" ]]; then
      echo "Creating Runtime Directory"
      mkdir $RUNDIR
    fi

    if [[ -a "$RUNDIR/assignment-client" && -a "$RUNDIR/domain-server" && -d "$RUNDIR/resources" ]]; then
      echo "Removing Old Last-Compile Backup"
      rm -rf $LASTCOMPILE/*

      echo "Backing Up AC"
      mv "$RUNDIR/assignment-client" $LASTCOMPILE

      echo "Backing Up DS"
      mv "$RUNDIR/domain-server" $LASTCOMPILE

      echo "Making a Copy Of The Resources Folder"
      cp -R "$RUNDIR/resources" $LASTCOMPILE
    fi

    if [[ ! -d $LOGSDIR ]]; then
      mkdir $LOGSDIR
    fi
    popd > /dev/null
  fi
}

function handlecmake {
  if [[ ! -f "cmake-3.0.2.tar.gz" ]]; then
    wget http://www.cmake.org/files/v3.0/cmake-3.0.2.tar.gz
    tar -xzvf cmake-3.0.2.tar.gz
    cd cmake-3.0.2/
    ./configure --prefix=/usr
    gmake && gmake install
    cd ..
  fi
}

function handleglm {
  if [[ ! -d "/usr/include/glm" ]]; then
    wget http://softlayer-dal.dl.sourceforge.net/project/ogl-math/glm-0.9.5.4/glm-0.9.5.4.zip
    unzip glm-0.9.5.4.zip
    mv glm/glm /usr/include
  fi
}

function handlebullet283 {
  if [ ! -f "Bullet-2.83-alpha.tar.gz" ]; then
    wget https://github.com/bulletphysics/bullet3/archive/Bullet-2.83-alpha.tar.gz
    tar -xzvf Bullet-2.83-alpha.tar.gz
    cd bullet3-Bullet-2.83-alpha/
    cmake -G "Unix Makefiles"
    make && make install
    cd ..
  fi
}

function handlebullet282 {
  #https://bullet.googlecode.com/files/bullet-2.82-r2704.zip
  if [ ! -f "bullet-2.82-r2704.zip" ]; then
    wget https://bullet.googlecode.com/files/bullet-2.82-r2704.zip
    unzip bullet-2.82-r2704.zip
    cd bullet-2.82-r2704
    cmake -G "Unix Makefiles"
    make && make install
    cd ..
  fi
}

function compilehifi {
  # NOTE - This currently assumes /usr/local/src and does not move forward if the source dir does not exist - todo: fix
  if [[ -d "$SRCDIR" ]]; then
    pushd $SRCDIR > /dev/null

    # handle install and compile of cmake
    if [[ ! -f "/usr/bin/cmake"  ]]; then
      handlecmake
    fi

    # Handle GLM Check/Install
    handleglm
     
    # Handle BulletSim
    # Check for a file from the default BulletSim Install
    if [[ ! -a "/usr/local/lib/cmake/bullet/BulletConfig.cmake" || $(cat /usr/local/lib/cmake/bullet/BulletConfig.cmake) =~ "2.83" ]]; then
      handlebullet282
      NEWHIFI=1      
    fi

    if [[ ! -d "highfidelity" ]]; then
      mkdir highfidelity
    fi

    cd highfidelity

    if [[ ! -d "gverb" ]]; then
      git clone https://github.com/highfidelity/gverb.git
      NEWHIFI=1
    else
      # assumes this is the proper git directory, could check for .git folder to verify
      cd gverb
      git pull > /dev/null
      cd ..
    fi

    if [[ ! -d "hifi" ]]; then
      git clone https://github.com/highfidelity/hifi.git
      NEWHIFI=1
    fi
    
    # popd src
    popd > /dev/null
    pushd $SRCDIR/highfidelity/hifi > /dev/null 

    # Link gverb libs in with hifi interface directory
    # now new directory: /usr/local/src/highfidelity/hifi/libraries/audio-client/external/gverb/
    if [[ ! -L "$SRCDIR/highfidelity/hifi/libraries/audio-client/external/gverb/src" ]]; then
      ln -s $SRCDIR/highfidelity/gverb/src $SRCDIR/highfidelity/hifi/libraries/audio-client/external/gverb/src
    fi
    if [[ ! -L "$SRCDIR/highfidelity/hifi/libraries/audio-client/external/gverb/include" ]]; then
      ln -s $SRCDIR/highfidelity/gverb/include $SRCDIR/highfidelity/hifi/libraries/audio-client/external/gverb/include
    fi

    # Future todo - add a forcable call to the shell script to override this
    if [[ $(git pull) =~ "Already up-to-date." ]]; then
      echo "Already up to date with last commit."
    else
      NEWHIFI=1
    fi

    if [[ $NEWHIFI -eq 1 ]]; then
      echo "Source needs compiling."
      # we are still assumed to be in hifi directory
      if [[ -d "build" ]]; then
        rm -rf build/*
      else
        mkdir build
      fi
      cd build
      cmake ..
      make domain-server && make assignment-client
      setwebperm
    fi 
    # ^ Ending the git pull check

    # popd on hifi source dir
    popd > /dev/null
  fi
}

function setwebperm {
  chown -R hifi:hifi $SRCDIR/highfidelity/hifi/domain-server/resources/web
}

function movehifi {
  # least error checking here, we pretty much assume that if this is a new compile per the flag
  # then you have all the proper folders and files already.
  if [[ $NEWHIFI -eq 1  ]]; then
    killrunning
    setwebperm
    DSDIR="$SRCDIR/highfidelity/hifi/build/domain-server"
    ACDIR="$SRCDIR/highfidelity/hifi/build/assignment-client"
    cp $DSDIR/domain-server $RUNDIR
    cp -R $DSDIR/resources $RUNDIR
    cp $ACDIR/assignment-client $RUNDIR
    changeowner
  fi
}

## End Functions ##

# Make sure only root can run this
checkroot

# Handle Yum Install Commands
doyum

# Deal with the source code and compile highfidelity
compilehifi

# Make our HiFi user if needed
createuser

# setup hifi folders
setuphifidirs

# Copy new binaries then change owner
movehifi

# Copy commands to be run to .bashrc
writecommands

# Handle re-running the hifi stack as needed here
handlerunhifi
