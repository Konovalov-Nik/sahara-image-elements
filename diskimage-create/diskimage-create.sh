#!/bin/bash

set -e

while getopts "p:i:v:" opt; do
  case $opt in
    p)
      PLUGIN=$OPTARG
    ;;
    i)
      IMAGE_TYPE=$OPTARG
     ;;
    v)
      HADOOP_VERSION=$OPTARG
    ;;
    *)
      echo
      echo "Usage: $(basename $0) [-p vanilla|spark|hdp|idh] [-i ubuntu|fedora|centos] [-v 1|2|plain]"
      echo "'-p' is plugin version, '-i' is image type, '-v' is hadoop version"
      echo "You shouldn't specify hadoop version and image type for spark plugin"
      echo "You shouldn't specify image type for hdp plugin"
      echo "Version 'plain' could be specified for hdp plugin only"
      echo "By default all images for all plugins will be created"
      exit 1
    ;;
  esac
done

# Checks of input
if [ -n "$PLUGIN" -a "$PLUGIN" != "vanilla" -a "$PLUGIN" != "spark" -a "$PLUGIN" != "hdp" -a "$PLUGIN" != "idh" ]; then
  echo -e "Unknown plugin selected.\nAborting"
  exit 1
fi

if [ -n "$IMAGE_TYPE" -a "$IMAGE_TYPE" != "ubuntu" -a "$IMAGE_TYPE" != "fedora" -a "$IMAGE_TYPE" != "centos" ]; then
  echo -e "Unknown image type selected.\nAborting"
  exit 1
fi

if [ -n "$HADOOP_VERSION" -a "$HADOOP_VERSION" != "1" -a "$HADOOP_VERSION" != "2" -a "$HADOOP_VERSION" != "plain" ]; then
  echo -e "Unknown hadoop version selected.\nAborting"
  exit 1
fi

if [ "$PLUGIN" = "vanilla" -a "$HADOOP_VERSION" = "plain" ]; then
  echo "Impossible combination.\nAborting"
  exit 1
fi
#################

if [ -e /etc/os-release ]; then
  platform=$(head -1 /etc/os-release)
  if [ $platform = 'NAME="Ubuntu"' ]; then
    apt-get update -y
    apt-get install qemu kpartx git -y
  elif [ $platform = 'NAME=Fedora' ]; then
    yum update -y
    yum install qemu kpartx git -y
  fi
else
  platform=$(head -1 /etc/system-release | grep CentOS)
  if [ -z $platform ]; then
    yum update -y
    yum install qemu-kvm kpartx git -y
  else
    echo -e "Unknown Host OS. Impossible to build images.\nAborting"
  fi
fi

base_dir="$(dirname $(readlink -e $0))"

TEMP=$(mktemp -d diskimage-create.XXXXXX)
pushd $TEMP

export DIB_IMAGE_CACHE=$TEMP/.cache-image-create

# Working with repositories
# disk-image-builder repo

if [ -z $DIB_REPO_PATH ]; then
  git clone https://git.openstack.org/openstack/diskimage-builder
  DIB_REPO_PATH="$(pwd)/diskimage-builder"
fi

export PATH=$PATH:$DIB_REPO_PATH/bin

pushd $DIB_REPO_PATH
export DIB_COMMIT_ID=`git rev-parse HEAD`
popd

export ELEMENTS_PATH="$DIB_REPO_PATH/elements"

# savanna-image-elements repo

if [ -z $SIM_REPO_PATH ]; then
  SIM_REPO_PATH="$(dirname $base_dir)"
  if [ $(basename $SIM_REPO_PATH) != "savanna-image-elements" ]; then
    echo "Can't find Savanna-image-elements repository. Cloning it."
    git clone https://git.openstack.org/openstack/savanna-image-elements
    SIM_REPO_PATH="$(pwd)/savanna-image-elements"
  fi
fi

ELEMENTS_PATH=$ELEMENTS_PATH:$SIM_REPO_PATH/elements

pushd $SIM_REPO_PATH
export SAVANNA_ELEMENTS_COMMIT_ID=`git rev-parse HEAD`
popd

#############################
# Images for Vanilla plugin #
#############################

if [ -z "$PLUGIN" -o "$PLUGIN" = "vanilla" ]; then
  export JAVA_DOWNLOAD_URL=${JAVA_DOWNLOAD_URL:-"http://download.oracle.com/otn-pub/java/jdk/7u51-b13/jdk-7u51-linux-x64.tar.gz"}
  export OOZIE_DOWNLOAD_URL=${OOZIE_DOWNLOAD_URL:-"http://savanna-files.mirantis.com/oozie-4.0.0.tar.gz"}
  export HIVE_VERSION=${HIVE_VERSION:-"0.11.0"}

  ubuntu_elements_sequence="base vm ubuntu hadoop swift_hadoop oozie mysql hive play"
  fedora_elements_sequence="base vm fedora hadoop swift_hadoop oozie mysql hive play"
  centos_elements_sequence="vm rhel hadoop swift_hadoop oozie mysql hive redhat-lsb"

  # Workaround for https://bugs.launchpad.net/diskimage-builder/+bug/1204824
  # https://bugs.launchpad.net/savanna/+bug/1252684
  if [ -z "$IMAGE_TYPE" -o "$IMAGE_TYPE" = "centos" -o "$IMAGE_TYPE" = "fedora" ]; then
    if [ "$platform" = 'NAME="Ubuntu"' ]; then
      echo "**************************************************************"
      echo "WARNING: As a workaround for DIB bug 1204824, you are about to"
      echo "         create a Fedora and CentOS images that has SELinux    "
      echo "         disabled. Do not use these images in production.       "
      echo "**************************************************************"
      fedora_elements_sequence="$fedora_elements_sequence selinux-permissive"
      centos_elements_sequence="$centos_elements_sequence selinux-permissive"
      suffix=".selinux-permissive"
    fi
  fi

  if [ -n "$USE_MIRRORS" ]; then
    mirror_element=" apt-mirror"
    ubuntu_elements_sequence=$ubuntu_elements_sequence$mirror_element
    mirror_element=" yum-mirror"
    fedora_elements_sequence=$fedora_elements_sequence$mirror_element
  fi

  # Ubuntu cloud image
  if [ -z "$IMAGE_TYPE" -o "$IMAGE_TYPE" = "ubuntu" ]; then
    if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "1" ]; then
      export DIB_HADOOP_VERSION=${DIB_HADOOP_VERSION_1:-"1.2.1"}
      export ubuntu_image_name="ubuntu_savanna_vanilla_hadoop_1_latest"
      disk-image-create $ubuntu_elements_sequence -o $ubuntu_image_name
      mv $ubuntu_image_name.qcow2 ../
    fi
    if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "2" ]; then
      export DIB_HADOOP_VERSION=${DIB_HADOOP_VERSION_2:-"2.2.0"}
      export ubuntu_image_name="ubuntu_savanna_vanilla_hadoop_2_latest"
      disk-image-create $ubuntu_elements_sequence -o $ubuntu_image_name
      mv $ubuntu_image_name.qcow2 ../
    fi
  fi

  # Fedora cloud image
  if [ -z "$IMAGE_TYPE" -o "$IMAGE_TYPE" = "fedora" ]; then
    if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "1" ]; then
      export DIB_HADOOP_VERSION=${DIB_HADOOP_VERSION_1:-"1.2.1"}
      export fedora_image_name="fedora_savanna_vanilla_hadoop_1_latest$suffix"
      disk-image-create $fedora_elements_sequence -o $fedora_image_name
      mv $fedora_image_name.qcow2 ../
    fi
    if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "2" ]; then
      export DIB_HADOOP_VERSION=${DIB_HADOOP_VERSION_2:-"2.2.0"}
      export fedora_image_name="fedora_savanna_vanilla_hadoop_2_latest$suffix"
      disk-image-create $fedora_elements_sequence -o $fedora_image_name
      mv $fedora_image_name.qcow2 ../
    fi
  fi

  # CentOS cloud image:
  # - Disable including 'base' element for CentOS
  # - Export link and filename for CentOS cloud image to download
  # - Patameter 'DIB_IMAGE_SIZE' should be specified for CentOS only
  if [ -z "$IMAGE_TYPE" -o "$IMAGE_TYPE" = "centos" ]; then
    export DIB_IMAGE_SIZE="10"
    # Read Create_CentOS_cloud_image.rst to know how to create CentOS image in qcow2 format
    export BASE_IMAGE_FILE="CentOS-6.5-cloud-init.qcow2"
    export DIB_CLOUD_IMAGES="http://savanna-files.mirantis.com"
    if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "1" ]; then
      export DIB_HADOOP_VERSION=${DIB_HADOOP_VERSION_1:-"1.2.1"}
      export centos_image_name="centos_savanna_vanilla_hadoop_1_latest$suffix"
      disk-image-create $centos_elements_sequence -n -o $centos_image_name
      mv $centos_image_name.qcow2 ../
    fi
    if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "2" ]; then
      export DIB_HADOOP_VERSION=${DIB_HADOOP_VERSION_2:-"2.2.0"}
      export centos_image_name="centos_savanna_vanilla_hadoop_2_latest$suffix"
      disk-image-create $centos_elements_sequence -n -o $centos_image_name
      mv $centos_image_name.qcow2 ../
    fi
  fi
fi

##########################
# Image for Spark plugin #
##########################

if [ -z "$PLUGIN" -o "$PLUGIN" = "spark" ]; then
  # Ignoring image type and hadoop version options
  echo "For spark plugin options -i and -v are ignored"

  export DIB_HADOOP_VERSION="2.0.0-mr1-cdh4.5.0"
  export ubuntu_image_name="ubuntu_savanna_spark_latest"

  ubuntu_elements_sequence="base vm ubuntu hadoop-cdh spark"

  if [ -n "$USE_MIRRORS" ]; then
    mirror_element=" apt-mirror"
    ubuntu_elements_sequence=$ubuntu_elements_sequence$mirror_element
  fi

  # Creating Ubuntu cloud image
  disk-image-create $ubuntu_elements_sequence -o $ubuntu_image_name
  mv $ubuntu_image_name.qcow2 ../
fi

#########################
# Images for HDP plugin #
#########################

if [ -z "$PLUGIN" -o "$PLUGIN" = "hdp" ]; then
  echo "For hdp plugin option -i is ignored"

  # Generate HDP images

  # Parameter 'DIB_IMAGE_SIZE' should be specified for Fedora and CentOS
  export DIB_IMAGE_SIZE="10"

  # CentOS cloud image:
  # - Disable including 'base' element for CentOS
  # - Export link and filename for CentOS cloud image to download
  export BASE_IMAGE_FILE="CentOS-6.4-cloud-init.qcow2"
  export DIB_CLOUD_IMAGES="http://savanna-files.mirantis.com"

  # Each image has a root login, password is "hadoop"
  export DIB_PASSWORD="hadoop"

  # Ignoring image type option
  if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "1" ]; then
    export centos_image_name_hdp_1_3="centos-6_4-64-hdp-1-3"
    # Elements to include in an HDP-based image
    centos_elements_sequence="vm rhel hadoop-hdp redhat-lsb root-passwd savanna-version source-repositories yum"
    # generate image with HDP 1.3
    export DIB_HDP_VERSION="1.3"
    disk-image-create $centos_elements_sequence -n -o $centos_image_name_hdp_1_3
    mv $centos_image_name_hdp_1_3.qcow2 ../
  fi

  if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "2" ]; then
    export centos_image_name_hdp_2_0="centos-6_4-64-hdp-2-0"
    # Elements to include in an HDP-based image
    centos_elements_sequence="vm rhel hadoop-hdp redhat-lsb root-passwd savanna-version source-repositories yum"
    # generate image with HDP 2.0
    export DIB_HDP_VERSION="2.0"
    disk-image-create $centos_elements_sequence -n -o $centos_image_name_hdp_2_0
    mv $centos_image_name_hdp_2_0.qcow2 ../
  fi

  if [ -z "$HADOOP_VERSION" -o "$HADOOP_VERSION" = "plain" ]; then
    export centos_image_name_plain="centos-6_4-64-plain"
    # Elements for a plain CentOS image that does not contain HDP or Apache Hadoop
    centos_plain_elements_sequence="vm rhel redhat-lsb root-passwd savanna-version yum"
    # generate plain (no Hadoop components) image for testing
    disk-image-create $centos_plain_elements_sequence -n -o $centos_image_name_plain
    mv $centos_image_name_plain.qcow2 ../
  fi
fi

########################
# Image for IDH plugin #
########################

if [ -z "$PLUGIN" -o "$PLUGIN" = "idh" ]; then
  # Ignoring image type and hadoop version options
  echo "For idh plugin options -i and -v are ignored"

  export DIB_IMAGE_SIZE="10"
  export BASE_IMAGE_FILE="CentOS-6.4-cloud-init.qcow2"
  export DIB_CLOUD_IMAGES="http://savanna-files.mirantis.com"
  export centos_image_name_idh="centos_savanna_idh_latest"

  centos_elements_sequence="vm rhel hadoop-idh"

  if [ "$platform" = 'NAME="Ubuntu"' ]; then
      echo "**************************************************************"
      echo "WARNING: As a workaround for DIB bug 1204824, you are about to"
      echo "         create a CentOS image that has SELinux               "
      echo "         disabled. Do not use these images in production.     "
      echo "**************************************************************"
      centos_elements_sequence="$centos_elements_sequence selinux-permissive"
      centos_image_name_idh="$centos_image_name_idh.selinux-permissive"
  fi

  disk-image-create $centos_elements_sequence -o $centos_image_name_idh
  mv $centos_image_name_idh.qcow2 ../
fi

popd # out of $TEMP
rm -rf $TEMP
