# Dockerfile for BendersNetworkDesign.jl with Gurobi support
FROM julia:1.12

USER root

# Suppress debconf warnings and install wget
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends wget && \
    rm -rf /var/lib/apt/lists/*

# Install Gurobi 12.0.0
RUN cd /opt && \
    wget -q https://packages.gurobi.com/12.0/gurobi12.0.0_linux64.tar.gz && \
    tar xzf gurobi12.0.0_linux64.tar.gz && \
    ln -s gurobi1200 gurobi && \
    rm gurobi12.0.0_linux64.tar.gz

# Configure Gurobi license for RWTH
RUN echo "TOKENSERVER=license.itc.rwth-aachen.de" > /opt/gurobi/gurobi.lic && \
    echo "PORT=50039" >> /opt/gurobi/gurobi.lic

# Set Gurobi environment variables
ENV GUROBI_HOME=/opt/gurobi/linux64
ENV PATH=$PATH:$GUROBI_HOME/bin
ENV LD_LIBRARY_PATH=$GUROBI_HOME/lib
ENV GRB_LICENSE_FILE=/opt/gurobi/gurobi.lic

WORKDIR /workspace
