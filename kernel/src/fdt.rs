/// fdt.rs - Flat Device Tree support

// Structure of a device tree:
//
// FDT Header
// ... empty space ...
// Memory reservation block
// ... empty space ...
// Structure block
// ... empty space ...
// Strings block
// ... empty space ...

// this value is 0xd00dfeed in big-endian, but since we're a little-endian system,
// let's avoid doing byte swapping.
const FDT_MAGIC: u32 = 0xedfe0dd0;

#[derive(Debug, Clone)]
pub enum FdtErrorType {
    BadMagic,
}

#[derive(Debug, Clone)]
pub struct FdtHeaderError {
    error_type: FdtErrorType,
}

#[derive(Debug)]
#[repr(C)]
pub struct FdtHeader {
    magic: u32,
    total_size: u32,
    pub offset_dt_struct: u32,
    pub offset_mem_reservation_map: u32,
    version: u32,
    last_comp_version: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
}

#[derive(Clone, Debug)]
#[repr(C)]
pub struct MemoryReservationEntry {
    pub address: u64,
    pub size: u64,
}

#[repr(u32)]
pub enum StructureToken {
    BeginNode = 0x00000001,
    EndNode = 0x00000002,
    Prop = 0x00000003,
    NOP = 0x00000004,
    End = 0x00000009,
}

#[repr(C)]
pub struct FdtProp {
    length: u32,
    name_offset: u32,
}

pub fn check_fdt(header: &FdtHeader) -> Result<(), FdtHeaderError> {
    if header.magic != FDT_MAGIC {
        return Err(FdtHeaderError {
            error_type: FdtErrorType::BadMagic,
        });
    }

    Ok(())
}

pub fn fetch_memory_reservation(location: usize) -> (Option<MemoryReservationEntry>, usize) {
    unsafe {
        let ptr = location as *mut u64;
        let reservation = ptr as *const MemoryReservationEntry;

        if (*reservation).address == 0 && (*reservation).size == 0 {
            return (None, 0);
        }

        return (Some((*reservation).clone()), ptr.add(2) as usize);
    }
}
