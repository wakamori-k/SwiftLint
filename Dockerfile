# Explicitly specify `jammy` to keep the Swift & Ubuntu images in sync.
ARG BUILDER_IMAGE=swift:jammy
ARG RUNTIME_IMAGE=ubuntu:jammy

# builder image
FROM ${BUILDER_IMAGE} AS builder
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libxml2-dev \
 && rm -r /var/lib/apt/lists/*
WORKDIR /workdir/
COPY Plugins Plugins/
COPY Source Source/
COPY Tests Tests/
COPY Package.* ./

RUN ln -s /usr/lib/swift/_InternalSwiftSyntaxParser .

RUN swift package update
ARG SWIFT_FLAGS="-c release -Xswiftc -static-stdlib -Xlinker -lCFURLSessionInterface -Xlinker -lCFXMLInterface -Xlinker -lcurl -Xlinker -lxml2 -Xswiftc -I. -Xlinker -fuse-ld=lld -Xlinker -L/usr/lib/swift/linux"
RUN swift run $SWIFT_FLAGS swiftlint version
RUN mkdir -p /executables
RUN install -v `swift build $SWIFT_FLAGS --show-bin-path`/swiftlint /executables

# runtime image
FROM ${RUNTIME_IMAGE}
LABEL org.opencontainers.image.source https://github.com/realm/SwiftLint
RUN apt-get update && apt-get install -y \
    libcurl4 \
    libxml2 \
 && rm -r /var/lib/apt/lists/*
COPY --from=builder /usr/lib/libsourcekitdInProc.so /usr/lib
COPY --from=builder /usr/lib/swift/linux/libBlocksRuntime.so /usr/lib
COPY --from=builder /usr/lib/swift/linux/libdispatch.so /usr/lib
COPY --from=builder /usr/lib/swift/linux/lib_InternalSwiftSyntaxParser.so /usr/lib
COPY --from=builder /executables/* /usr/bin

RUN swiftlint version

CMD ["swiftlint"]
