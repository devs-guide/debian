#include <cuda_runtime.h>

#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

__global__ void deterministic_vector(const unsigned int* input, unsigned int* output, size_t count) {
  const size_t index = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
  if (index < count) {
    output[index] = input[index] * 3U + 17U;
  }
}

int fail(const char* stage, cudaError_t error, const char* pci_bus_id = "") {
  std::printf(
      "{\"test\":\"cuda-smoke\",\"passed\":false,\"stage\":\"%s\","
      "\"pci_bus_id\":\"%s\",\"cuda_error\":\"%s\"}\n",
      stage, pci_bus_id, cudaGetErrorString(error));
  return 1;
}

}  // namespace

int main() {
  constexpr size_t kElementCount = 1U << 20;
  constexpr size_t kBytes = kElementCount * sizeof(unsigned int);
  int visible_devices = 0;
  cudaError_t error = cudaGetDeviceCount(&visible_devices);
  if (error != cudaSuccess) {
    return fail("cudaGetDeviceCount", error);
  }
  if (visible_devices != 1) {
    std::printf(
        "{\"test\":\"cuda-smoke\",\"passed\":false,"
        "\"visible_device_count\":%d,\"cuda_error\":\"expected exactly one visible CUDA device\"}\n",
        visible_devices);
    return 1;
  }

  cudaDeviceProp properties{};
  error = cudaGetDeviceProperties(&properties, 0);
  if (error != cudaSuccess) {
    return fail("cudaGetDeviceProperties", error);
  }
  char pci_bus_id[32] = {};
  error = cudaDeviceGetPCIBusId(pci_bus_id, sizeof(pci_bus_id), 0);
  if (error != cudaSuccess) {
    return fail("cudaDeviceGetPCIBusId", error);
  }

  std::vector<unsigned int> host_input(kElementCount);
  std::vector<unsigned int> host_output(kElementCount, 0U);
  for (size_t index = 0; index < kElementCount; ++index) {
    host_input[index] = static_cast<unsigned int>((index * 2654435761ULL) ^ 0x5a5a5a5aU);
  }

  unsigned int* device_input = nullptr;
  unsigned int* device_output = nullptr;
  error = cudaMalloc(&device_input, kBytes);
  if (error != cudaSuccess) {
    return fail("cudaMalloc(input)", error, pci_bus_id);
  }
  error = cudaMalloc(&device_output, kBytes);
  if (error != cudaSuccess) {
    cudaFree(device_input);
    return fail("cudaMalloc(output)", error, pci_bus_id);
  }
  error = cudaMemcpy(device_input, host_input.data(), kBytes, cudaMemcpyHostToDevice);
  if (error != cudaSuccess) {
    cudaFree(device_output);
    cudaFree(device_input);
    return fail("cudaMemcpy(host-to-device)", error, pci_bus_id);
  }

  constexpr unsigned int kThreads = 256;
  const unsigned int blocks = static_cast<unsigned int>((kElementCount + kThreads - 1) / kThreads);
  deterministic_vector<<<blocks, kThreads>>>(device_input, device_output, kElementCount);
  error = cudaGetLastError();
  if (error != cudaSuccess) {
    cudaFree(device_output);
    cudaFree(device_input);
    return fail("kernel-launch", error, pci_bus_id);
  }
  error = cudaDeviceSynchronize();
  if (error != cudaSuccess) {
    cudaFree(device_output);
    cudaFree(device_input);
    return fail("cudaDeviceSynchronize", error, pci_bus_id);
  }
  error = cudaMemcpy(host_output.data(), device_output, kBytes, cudaMemcpyDeviceToHost);
  cudaFree(device_output);
  cudaFree(device_input);
  if (error != cudaSuccess) {
    return fail("cudaMemcpy(device-to-host)", error, pci_bus_id);
  }

  for (size_t index = 0; index < kElementCount; ++index) {
    if (host_output[index] != host_input[index] * 3U + 17U) {
      std::printf(
          "{\"test\":\"cuda-smoke\",\"passed\":false,\"pci_bus_id\":\"%s\","
          "\"mismatch_index\":%zu,\"cuda_error\":null}\n",
          pci_bus_id, index);
      return 1;
    }
  }

  std::printf(
      "{\"test\":\"cuda-smoke\",\"passed\":true,\"visible_device_count\":1,"
      "\"device_ordinal\":0,\"device_name\":\"%s\",\"pci_bus_id\":\"%s\","
      "\"compute_capability\":\"%d.%d\",\"memory_total_bytes\":%zu,"
      "\"elements_checked\":%zu,\"cuda_error\":null}\n",
      properties.name, pci_bus_id, properties.major, properties.minor,
      static_cast<size_t>(properties.totalGlobalMem), kElementCount);
  return 0;
}
