#include <cuda_runtime.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

__global__ void remote_write(unsigned int* destination, size_t count, unsigned int seed) {
  const size_t index = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
  if (index < count) {
    destination[index] = static_cast<unsigned int>(index) ^ seed;
  }
}

const char* value_after(const char* argument, const char* name) {
  const size_t name_length = std::strlen(name);
  return std::strncmp(argument, name, name_length) == 0 ? argument + name_length : nullptr;
}

struct DirectionResult {
  bool passed = false;
  bool can_access_peer = false;
  bool peer_enable_passed = false;
  bool remote_kernel_passed = false;
  bool peer_copy_passed = false;
  double bandwidth_gib_s = 0.0;
  double latency_us = 0.0;
  std::string error;
};

void set_error(DirectionResult* result, const char* stage, cudaError_t error) {
  result->error = std::string(stage) + ": " + cudaGetErrorString(error);
}

DirectionResult run_direction(int source, int destination, size_t bytes, int iterations) {
  DirectionResult result;
  int can_access = 0;
  cudaError_t error = cudaDeviceCanAccessPeer(&can_access, source, destination);
  if (error != cudaSuccess) {
    set_error(&result, "cudaDeviceCanAccessPeer", error);
    return result;
  }
  result.can_access_peer = can_access != 0;
  if (!result.can_access_peer) {
    result.error = "cudaDeviceCanAccessPeer returned false";
    return result;
  }

  error = cudaSetDevice(source);
  if (error != cudaSuccess) {
    set_error(&result, "cudaSetDevice(source)", error);
    return result;
  }
  bool peer_enabled_here = false;
  error = cudaDeviceEnablePeerAccess(destination, 0);
  if (error == cudaSuccess) {
    peer_enabled_here = true;
  } else if (error != cudaErrorPeerAccessAlreadyEnabled) {
    set_error(&result, "cudaDeviceEnablePeerAccess", error);
    return result;
  }
  result.peer_enable_passed = true;

  constexpr size_t kKernelElements = 1U << 20;
  constexpr size_t kKernelBytes = kKernelElements * sizeof(unsigned int);
  unsigned int* remote_kernel_buffer = nullptr;
  unsigned int* source_buffer = nullptr;
  unsigned int* destination_buffer = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;
  std::vector<unsigned int> host(kKernelElements);
  std::vector<unsigned int> copy_input;
  std::vector<unsigned int> copy_output;
  float elapsed_ms = 0.0F;

  error = cudaSetDevice(destination);
  if (error == cudaSuccess) error = cudaMalloc(&remote_kernel_buffer, kKernelBytes);
  if (error != cudaSuccess) {
    set_error(&result, "cudaMalloc(remote-kernel-buffer)", error);
    goto cleanup;
  }
  error = cudaSetDevice(source);
  if (error == cudaSuccess) {
    remote_write<<<static_cast<unsigned int>((kKernelElements + 255) / 256), 256>>>(remote_kernel_buffer, kKernelElements, 0x9e3779b9U);
    error = cudaGetLastError();
  }
  if (error == cudaSuccess) error = cudaDeviceSynchronize();
  if (error != cudaSuccess) {
    set_error(&result, "remote-kernel-write", error);
    goto cleanup;
  }
  error = cudaSetDevice(destination);
  if (error == cudaSuccess) error = cudaMemcpy(host.data(), remote_kernel_buffer, kKernelBytes, cudaMemcpyDeviceToHost);
  if (error != cudaSuccess) {
    set_error(&result, "remote-kernel-readback", error);
    goto cleanup;
  }
  for (size_t index = 0; index < kKernelElements; ++index) {
    if (host[index] != (static_cast<unsigned int>(index) ^ 0x9e3779b9U)) {
      result.error = "remote-kernel data mismatch";
      goto cleanup;
    }
  }
  result.remote_kernel_passed = true;

  error = cudaSetDevice(source);
  if (error == cudaSuccess) error = cudaMalloc(&source_buffer, bytes);
  if (error == cudaSuccess) error = cudaSetDevice(destination);
  if (error == cudaSuccess) error = cudaMalloc(&destination_buffer, bytes);
  if (error != cudaSuccess) {
    set_error(&result, "cudaMalloc(peer-copy-buffer)", error);
    goto cleanup;
  }
  copy_input.resize(bytes / sizeof(unsigned int));
  copy_output.assign(copy_input.size(), 0U);
  for (size_t index = 0; index < copy_input.size(); ++index) copy_input[index] = static_cast<unsigned int>(index) ^ 0xa5a5a5a5U;
  error = cudaSetDevice(source);
  if (error == cudaSuccess) error = cudaMemcpy(source_buffer, copy_input.data(), bytes, cudaMemcpyHostToDevice);
  if (error == cudaSuccess) error = cudaMemcpyPeerAsync(destination_buffer, destination, source_buffer, source, bytes, nullptr);
  if (error == cudaSuccess) error = cudaDeviceSynchronize();
  if (error == cudaSuccess) error = cudaSetDevice(destination);
  if (error == cudaSuccess) error = cudaMemcpy(copy_output.data(), destination_buffer, bytes, cudaMemcpyDeviceToHost);
  if (error != cudaSuccess) {
    set_error(&result, "cudaMemcpyPeerAsync(correctness)", error);
    goto cleanup;
  }
  if (copy_input != copy_output) {
    result.error = "peer-copy data mismatch";
    goto cleanup;
  }
  result.peer_copy_passed = true;

  error = cudaSetDevice(source);
  if (error == cudaSuccess) error = cudaEventCreate(&start);
  if (error == cudaSuccess) error = cudaEventCreate(&stop);
  if (error != cudaSuccess) {
    set_error(&result, "cudaEventCreate", error);
    goto cleanup;
  }
  for (int iteration = 0; iteration < 5; ++iteration) {
    error = cudaMemcpyPeerAsync(destination_buffer, destination, source_buffer, source, bytes, nullptr);
    if (error != cudaSuccess) break;
  }
  if (error == cudaSuccess) error = cudaDeviceSynchronize();
  if (error == cudaSuccess) error = cudaEventRecord(start, nullptr);
  for (int iteration = 0; error == cudaSuccess && iteration < iterations; ++iteration) {
    error = cudaMemcpyPeerAsync(destination_buffer, destination, source_buffer, source, bytes, nullptr);
  }
  if (error == cudaSuccess) error = cudaEventRecord(stop, nullptr);
  if (error == cudaSuccess) error = cudaEventSynchronize(stop);
  if (error == cudaSuccess) error = cudaEventElapsedTime(&elapsed_ms, start, stop);
  if (error != cudaSuccess || elapsed_ms <= 0.0F) {
    set_error(&result, "peer-copy-bandwidth", error == cudaSuccess ? cudaErrorUnknown : error);
    goto cleanup;
  }
  result.bandwidth_gib_s = (static_cast<double>(bytes) * iterations) / (elapsed_ms / 1000.0) / (1024.0 * 1024.0 * 1024.0);
  result.latency_us = (elapsed_ms * 1000.0) / iterations;
  result.passed = true;

cleanup:
  if (start != nullptr) cudaEventDestroy(start);
  if (stop != nullptr) cudaEventDestroy(stop);
  if (source_buffer != nullptr) { cudaSetDevice(source); cudaFree(source_buffer); }
  if (destination_buffer != nullptr) { cudaSetDevice(destination); cudaFree(destination_buffer); }
  if (remote_kernel_buffer != nullptr) { cudaSetDevice(destination); cudaFree(remote_kernel_buffer); }
  if (peer_enabled_here) { cudaSetDevice(source); cudaDeviceDisablePeerAccess(destination); }
  return result;
}

void print_result(const DirectionResult& result, const char* source_uuid, const char* destination_uuid) {
  std::printf(
      "{\"test\":\"p2p\",\"source_uuid\":\"%s\",\"destination_uuid\":\"%s\","
      "\"can_access_peer\":%s,\"peer_enable_passed\":%s,\"remote_kernel_passed\":%s,"
      "\"peer_copy_passed\":%s,\"unidirectional_gib_s\":%.6f,\"latency_us\":%.3f,"
      "\"cuda_error\":%s}\n",
      source_uuid, destination_uuid,
      result.can_access_peer ? "true" : "false", result.peer_enable_passed ? "true" : "false",
      result.remote_kernel_passed ? "true" : "false", result.peer_copy_passed ? "true" : "false",
      result.bandwidth_gib_s, result.latency_us,
      result.error.empty() ? "null" : ("\"" + result.error + "\"").c_str());
}

}  // namespace

int main(int argc, char** argv) {
  size_t buffer_mib = 256;
  int iterations = 20;
  const char* uuid_a = "visible-device-0";
  const char* uuid_b = "visible-device-1";
  for (int index = 1; index < argc; ++index) {
    if (const char* value = value_after(argv[index], "--buffer-mib=")) buffer_mib = static_cast<size_t>(std::strtoull(value, nullptr, 10));
    else if (const char* value = value_after(argv[index], "--iterations=")) iterations = std::atoi(value);
    else if (const char* value = value_after(argv[index], "--source-uuid=")) uuid_a = value;
    else if (const char* value = value_after(argv[index], "--destination-uuid=")) uuid_b = value;
    else { std::fprintf(stderr, "unsupported argument: %s\n", argv[index]); return 64; }
  }
  if (buffer_mib == 0 || iterations <= 0) { std::fprintf(stderr, "buffer-mib and iterations must be positive\n"); return 64; }
  int visible_devices = 0;
  cudaError_t error = cudaGetDeviceCount(&visible_devices);
  if (error != cudaSuccess || visible_devices != 2) {
    std::printf("{\"test\":\"p2p\",\"passed\":false,\"cuda_error\":\"expected exactly two visible CUDA devices\"}\n");
    return 1;
  }
  const size_t bytes = buffer_mib * 1024ULL * 1024ULL;
  if (bytes % sizeof(unsigned int) != 0) return 64;
  const DirectionResult forward = run_direction(0, 1, bytes, iterations);
  const DirectionResult reverse = run_direction(1, 0, bytes, iterations);
  print_result(forward, uuid_a, uuid_b);
  print_result(reverse, uuid_b, uuid_a);
  return forward.passed && reverse.passed ? 0 : 1;
}
