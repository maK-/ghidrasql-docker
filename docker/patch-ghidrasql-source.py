#!/usr/bin/env python3
"""Apply LibGhidraHost ranged-scan patches to ghidrasql source_libghidra.cpp."""

from __future__ import annotations

import sys
from pathlib import Path

SOURCE = Path("/opt/src/ghidrasql/src/lib/src/source_libghidra.cpp")

OLD_FUNCTIONS = """    bool read_functions(std::vector<model::FunctionRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;
        return paginate_locked(2048, out, [&](int ps, int off, auto& dest, std::size_t& count) {
            trace_rpc_locked("ListFunctions");
            auto listed = client_.ListFunctions(kAllAddressesMin, kAllAddressesMax, ps, off);
            if (!ok_or_record_error_locked(listed, "ListFunctions")) return false;
            const auto& rows = listed.value->functions;
            count = rows.size();
            dest.reserve(dest.size() + count);
            for (const auto& row : rows) {
                dest.push_back(map_function(row));
            }
            return true;
        });
    }"""

NEW_FUNCTIONS = """    bool read_functions(std::vector<model::FunctionRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;

        // Work around LibGhidraHost behavior where an all-address-space
        // ListFunctions(0, UINT64_MAX, ...) request can return zero rows even
        // though ranged ListFunctions(start, end, ...) over executable memory
        // blocks returns the analyzed functions.
        std::vector<libghidra::client::MemoryBlockRecord> blocks;
        if (!paginate_locked(256, blocks, [&](int ps, int off, auto& dest, std::size_t& count) {
                auto listed = client_.ListMemoryBlocks(ps, off);
                if (!ok_or_record_error_locked(listed, "ListMemoryBlocks")) return false;
                const auto& rows = listed.value->blocks;
                count = rows.size();
                dest.reserve(dest.size() + count);
                for (const auto& row : rows) {
                    dest.push_back(row);
                }
                return true;
            })) {
            return false;
        }

        std::unordered_set<std::uint64_t> seen;
        for (const auto& block : blocks) {
            if (!block.is_execute) {
                continue;
            }

            const auto start = block.start_address;
            const auto range_end = block.end_address;
            if (range_end < start) {
                continue;
            }

            int off = 0;
            while (true) {
                trace_rpc_locked("ListFunctions");
                auto listed = client_.ListFunctions(start, range_end, 2048, off);
                if (!ok_or_record_error_locked(listed, "ListFunctions")) return false;

                const auto& rows = listed.value->functions;
                if (rows.empty()) {
                    break;
                }

                out.reserve(out.size() + rows.size());
                for (const auto& row : rows) {
                    if (seen.insert(row.entry_address).second) {
                        out.push_back(map_function(row));
                    }
                }

                if (rows.size() < 2048) {
                    break;
                }
                off += static_cast<int>(rows.size());
            }
        }

        std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
            return a.address < b.address;
        });

        last_error_.clear();
        return true;
    }"""

OLD_INSTRUCTIONS = """    bool read_instructions(std::vector<model::InstructionRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;
        return paginate_locked(4096, out, [&](int ps, int off, auto& dest, std::size_t& count) {
            auto listed = client_.ListInstructions(kAllAddressesMin, kAllAddressesMax, ps, off);
            if (!ok_or_record_error_locked(listed, "ListInstructions")) return false;
            const auto& rows = listed.value->instructions;
            count = rows.size();
            dest.reserve(dest.size() + count);
            for (const auto& row : rows) {
                dest.push_back(map_instruction(row));
            }
            return true;
        });
    }"""

NEW_INSTRUCTIONS = """    bool read_instructions(std::vector<model::InstructionRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;

        std::vector<libghidra::client::MemoryBlockRecord> blocks;
        if (!paginate_locked(256, blocks, [&](int ps, int off, auto& dest, std::size_t& count) {
                auto listed = client_.ListMemoryBlocks(ps, off);
                if (!ok_or_record_error_locked(listed, "ListMemoryBlocks")) return false;
                const auto& rows = listed.value->blocks;
                count = rows.size();
                dest.reserve(dest.size() + count);
                for (const auto& row : rows) {
                    dest.push_back(row);
                }
                return true;
            })) {
            return false;
        }

        std::unordered_set<std::uint64_t> seen;
        for (const auto& block : blocks) {
            if (!block.is_execute) {
                continue;
            }

            const auto start = block.start_address;
            const auto range_end = block.end_address;
            if (range_end < start) {
                continue;
            }

            int off = 0;
            while (true) {
                auto listed = client_.ListInstructions(start, range_end, 4096, off);
                if (!ok_or_record_error_locked(listed, "ListInstructions")) return false;

                const auto& rows = listed.value->instructions;
                if (rows.empty()) {
                    break;
                }

                out.reserve(out.size() + rows.size());
                for (const auto& row : rows) {
                    if (seen.insert(row.address).second) {
                        out.push_back(map_instruction(row));
                    }
                }

                if (rows.size() < 4096) {
                    break;
                }
                off += static_cast<int>(rows.size());
            }
        }

        std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
            return a.address < b.address;
        });

        last_error_.clear();
        return true;
    }"""

OLD_SYMBOLS = """    bool read_symbols(std::vector<model::SymbolRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;
        return paginate_locked(4096, out, [&](int ps, int off, auto& dest, std::size_t& count) {
            auto listed = client_.ListSymbols(kAllAddressesMin, kAllAddressesMax, ps, off);
            if (!ok_or_record_error_locked(listed, "ListSymbols")) return false;
            const auto& rows = listed.value->symbols;
            count = rows.size();
            dest.reserve(dest.size() + count);
            for (const auto& row : rows) {
                dest.push_back(map_symbol(row));
            }
            return true;
        });
    }"""

NEW_SYMBOLS = """    bool read_symbols(std::vector<model::SymbolRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;

        std::vector<libghidra::client::MemoryBlockRecord> blocks;
        if (!paginate_locked(256, blocks, [&](int ps, int off, auto& dest, std::size_t& count) {
                auto listed = client_.ListMemoryBlocks(ps, off);
                if (!ok_or_record_error_locked(listed, "ListMemoryBlocks")) return false;
                const auto& rows = listed.value->blocks;
                count = rows.size();
                dest.reserve(dest.size() + count);
                for (const auto& row : rows) {
                    dest.push_back(row);
                }
                return true;
            })) {
            return false;
        }

        std::unordered_set<std::uint64_t> seen;
        for (const auto& block : blocks) {
            const auto start = block.start_address;
            const auto range_end = block.end_address;
            if (range_end < start) {
                continue;
            }

            int off = 0;
            while (true) {
                auto listed = client_.ListSymbols(start, range_end, 4096, off);
                if (!ok_or_record_error_locked(listed, "ListSymbols")) return false;

                const auto& rows = listed.value->symbols;
                if (rows.empty()) {
                    break;
                }

                out.reserve(out.size() + rows.size());
                for (const auto& row : rows) {
                    if (seen.insert(row.address).second) {
                        out.push_back(map_symbol(row));
                    }
                }

                if (rows.size() < 4096) {
                    break;
                }
                off += static_cast<int>(rows.size());
            }
        }

        std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
            return a.address < b.address;
        });

        last_error_.clear();
        return true;
    }"""

OLD_XREFS = """    bool read_xrefs(std::vector<model::XrefRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;
        return paginate_locked(4096, out, [&](int ps, int off, auto& dest, std::size_t& count) {
            auto listed = client_.ListXrefs(kAllAddressesMin, kAllAddressesMax, ps, off);
            if (!ok_or_record_error_locked(listed, "ListXrefs")) return false;
            const auto& rows = listed.value->xrefs;
            count = rows.size();
            dest.reserve(dest.size() + count);
            for (const auto& row : rows) {
                model::XrefRow mapped;
                mapped.from_ea = to_i64(row.from_address);
                mapped.to_ea = to_i64(row.to_address);
                mapped.kind = row.ref_type;
                mapped.is_code = row.is_flow ? 1 : 0;
                mapped.is_data = row.is_memory ? 1 : 0;
                dest.push_back(std::move(mapped));
            }
            return true;
        });
    }"""

NEW_XREFS = """    bool read_xrefs(std::vector<model::XrefRow>& out) const override {
        out.clear();
        std::lock_guard<std::mutex> lock(mu_);
        if (!ensure_session_open_locked()) return false;

        std::vector<libghidra::client::MemoryBlockRecord> blocks;
        if (!paginate_locked(256, blocks, [&](int ps, int off, auto& dest, std::size_t& count) {
                auto listed = client_.ListMemoryBlocks(ps, off);
                if (!ok_or_record_error_locked(listed, "ListMemoryBlocks")) return false;
                const auto& rows = listed.value->blocks;
                count = rows.size();
                dest.reserve(dest.size() + count);
                for (const auto& row : rows) {
                    dest.push_back(row);
                }
                return true;
            })) {
            return false;
        }

        std::unordered_set<std::string> seen;
        for (const auto& block : blocks) {
            const auto start = block.start_address;
            const auto range_end = block.end_address;
            if (range_end < start) {
                continue;
            }

            int off = 0;
            while (true) {
                auto listed = client_.ListXrefs(start, range_end, 4096, off);
                if (!ok_or_record_error_locked(listed, "ListXrefs")) return false;

                const auto& rows = listed.value->xrefs;
                if (rows.empty()) {
                    break;
                }

                out.reserve(out.size() + rows.size());
                for (const auto& row : rows) {
                    const std::string key =
                        std::to_string(row.from_address) + ":" +
                        std::to_string(row.to_address) + ":" +
                        row.ref_type;
                    if (!seen.insert(key).second) {
                        continue;
                    }

                    model::XrefRow mapped;
                    mapped.from_ea = to_i64(row.from_address);
                    mapped.to_ea = to_i64(row.to_address);
                    mapped.kind = row.ref_type;
                    mapped.is_code = row.is_flow ? 1 : 0;
                    mapped.is_data = row.is_memory ? 1 : 0;
                    out.push_back(std::move(mapped));
                }

                if (rows.size() < 4096) {
                    break;
                }
                off += static_cast<int>(rows.size());
            }
        }

        std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
            if (a.from_ea != b.from_ea) return a.from_ea < b.from_ea;
            return a.to_ea < b.to_ea;
        });

        last_error_.clear();
        return true;
    }"""


def main() -> int:
    if not SOURCE.is_file():
        print(f"ERROR: source file not found: {SOURCE}", file=sys.stderr)
        return 1

    content = SOURCE.read_text()
    replacements = [
        ("read_functions", OLD_FUNCTIONS, NEW_FUNCTIONS),
        ("read_instructions", OLD_INSTRUCTIONS, NEW_INSTRUCTIONS),
        ("read_symbols", OLD_SYMBOLS, NEW_SYMBOLS),
        ("read_xrefs", OLD_XREFS, NEW_XREFS),
    ]

    for name, old, new in replacements:
        if old not in content:
            print(f"ERROR: Could not find original {name} block in {SOURCE}", file=sys.stderr)
            return 1
        content = content.replace(old, new)
        print(f"Patched {name}")

    # Safety: libghidra renamed MemoryBlock -> MemoryBlockRecord
    typo = "std::vector<libghidra::client::MemoryBlock> blocks;"
    fixed = "std::vector<libghidra::client::MemoryBlockRecord> blocks;"
    if typo in content:
        content = content.replace(typo, fixed)
        print("Fixed MemoryBlock -> MemoryBlockRecord")

    SOURCE.write_text(content)
    print(f"Updated {SOURCE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
