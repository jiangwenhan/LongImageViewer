import Foundation

enum ProcessMemoryMonitor {
  static var usedBytes: UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size
        / MemoryLayout<integer_t>.size
    )

    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(
        to: integer_t.self,
        capacity: Int(count)
      ) { reboundPointer in
        task_info(
          mach_task_self_,
          task_flavor_t(TASK_VM_INFO),
          reboundPointer,
          &count
        )
      }
    }

    guard result == KERN_SUCCESS else { return nil }
    return UInt64(info.phys_footprint)
  }

  static var formattedUsedMemory: String {
    guard let usedBytes else { return "内存 --" }
    let mebibytes = Double(usedBytes) / 1_048_576
    return String(format: "内存 %.0f MB", mebibytes)
  }
}
