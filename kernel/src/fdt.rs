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

#[repr(C)]
pub struct FdtHeader {
    magic: u32,
    total_size: u32,
    offset_dt_struct: u32,
    offset_mem_reservation_map: u32,
    version: u32,
    last_comp_version: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
}

#[repr(C)]
pub struct MemoryReservationEntry {
    address: u64,
    size: u64,
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
