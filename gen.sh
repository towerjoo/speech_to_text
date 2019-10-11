#!/usr/bin/env bash
GOOGLEAPIS=/Users/tao/shadow/3rdparty/googleapis
PROTOBUF=/Users/tao/shadow/3rdparty/protobuf
PROTOC="protoc -I$GOOGLEAPIS -I$PROTOBUF/src --dart_out=grpc:lib/src/generated"

$PROTOC $PROTOBUF/src/google/protobuf/any.proto
$PROTOC $PROTOBUF/src/google/protobuf/duration.proto
$PROTOC $PROTOBUF/src/google/protobuf/empty.proto
$PROTOC $PROTOBUF/src/google/protobuf/struct.proto
$PROTOC $PROTOBUF/src/google/protobuf/timestamp.proto

$PROTOC $GOOGLEAPIS/google/rpc/status.proto
$PROTOC $GOOGLEAPIS/google/rpc/code.proto

$PROTOC $GOOGLEAPIS/google/longrunning/operations.proto

$PROTOC $GOOGLEAPIS/google/cloud/speech/v1/cloud_speech.proto
