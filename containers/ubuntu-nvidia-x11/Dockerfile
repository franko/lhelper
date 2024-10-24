# $LHELPER_DIR/containers/ubuntu-gtk-dev/Dockerfile
FROM ubuntu:focal

# Accept build arguments for user/group IDs and names
ARG USER_ID
ARG GROUP_ID
ARG USERNAME
ARG GROUPNAME

ENV __NV_PRIME_RENDER_OFFLOAD=1
ENV __GLX_VENDOR_LIBRARY_NAME=nvidia

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    sudo x11-apps xorg-dev build-essential pkg-config ninja-build \
    git python3-pip ca-certificates curl vim \
    bison libxcb-xkb-dev libegl1-mesa-dev openssh-client \
    mesa-utils libgl1-mesa-glx libgl1-mesa-dev \
    nvidia-driver-460 nvidia-utils-460 \
    --no-install-recommends \
    && pip3 install meson \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create the same group as host
RUN groupadd -g $GROUP_ID $GROUPNAME

# Create the same user as host
RUN useradd -m -u $USER_ID -g $GROUP_ID -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to the user
USER $USERNAME

# Set the working directory to user's home
WORKDIR /home/$USERNAME

# Setup user environment
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> .bashrc \
    && mkdir -p .local/bin

RUN git clone https://github.com/franko/lhelper && cd lhelper && \
  bash install $HOME/.local

WORKDIR /workspace

CMD ["/bin/bash"]
