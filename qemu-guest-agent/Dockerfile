FROM registry.access.redhat.com/ubi8/ubi
USER root
LABEL summary="The QEMU Guest Agent" \
      io.k8s.description="This package provides an agent to run inside guests, which communicates with the host over a virtio-serial channel named 'org.qemu.guest_agent.0'" \
      io.k8s.display-name="QEMU Guest Agent" \
      license="GPLv2+ and LGPLv2+ and BSD" \
      architecture="x86_64" \
      maintainer="Chris Keller <ckeller@redhat.com>"

COPY qemu-guest-agent-4.2.0-16.module+el8.2.0+6092+4f2391c1.x86_64.rpm /qemu-guest-agent-4.2.0-16.module+el8.2.0+6092+4f2391c1.x86_64.rpm
RUN rpm -ivh /qemu-guest-agent-4.2.0-16.module+el8.2.0+6092+4f2391c1.x86_64.rpm
