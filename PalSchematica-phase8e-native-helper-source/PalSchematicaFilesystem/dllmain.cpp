#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>

#include <Windows.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

using namespace RC;
namespace fs = std::filesystem;

namespace
{
    struct SchematicRecord
    {
        std::string file{};
        std::uintmax_t size{};
        std::int64_t modified_at{};
    };

    auto wide_to_utf8(const std::wstring& value) -> std::string
    {
        if (value.empty())
        {
            return {};
        }

        const int required_size = WideCharToMultiByte(
            CP_UTF8,
            0,
            value.data(),
            static_cast<int>(value.size()),
            nullptr,
            0,
            nullptr,
            nullptr
        );

        if (required_size <= 0)
        {
            return {};
        }

        std::string result(
            static_cast<std::size_t>(required_size),
            '\0'
        );

        WideCharToMultiByte(
            CP_UTF8,
            0,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            required_size,
            nullptr,
            nullptr
        );

        return result;
    }

    auto escape_json(const std::string& value) -> std::string
    {
        std::ostringstream output;

        for (const unsigned char character : value)
        {
            switch (character)
            {
            case '"':
                output << "\\\"";
                break;
            case '\\':
                output << "\\\\";
                break;
            case '\b':
                output << "\\b";
                break;
            case '\f':
                output << "\\f";
                break;
            case '\n':
                output << "\\n";
                break;
            case '\r':
                output << "\\r";
                break;
            case '\t':
                output << "\\t";
                break;
            default:
                if (character < 0x20)
                {
                    output
                        << "\\u"
                        << std::hex
                        << std::setw(4)
                        << std::setfill('0')
                        << static_cast<int>(character)
                        << std::dec;
                }
                else
                {
                    output << character;
                }
                break;
            }
        }

        return output.str();
    }

    auto executable_path() -> fs::path
    {
        std::wstring buffer(32768, L'\0');

        const DWORD length = GetModuleFileNameW(
            nullptr,
            buffer.data(),
            static_cast<DWORD>(buffer.size())
        );

        if (length == 0 || length >= buffer.size())
        {
            return {};
        }

        buffer.resize(length);
        return fs::path{buffer};
    }

    auto locate_game_root() -> fs::path
    {
        auto current = executable_path().parent_path();

        // Palworld\Pal\Binaries\Win64\Palworld-Win64-Shipping.exe
        // Ascend: Win64 -> Binaries -> Pal -> Palworld
        for (int index = 0; index < 3; ++index)
        {
            if (current.empty())
            {
                return {};
            }

            current = current.parent_path();
        }

        return current;
    }

    auto schematics_directory() -> fs::path
    {
        return locate_game_root()
            / L"Mods"
            / L"NativeMods"
            / L"UE4SS"
            / L"Mods"
            / L"PalSchematica"
            / L"Schematics";
    }

    auto file_time_to_unix_seconds(
        const fs::file_time_type& file_time
    ) -> std::int64_t
    {
        const auto system_time =
            std::chrono::time_point_cast<
                std::chrono::system_clock::duration
            >(
                file_time
                - fs::file_time_type::clock::now()
                + std::chrono::system_clock::now()
            );

        return std::chrono::duration_cast<
            std::chrono::seconds
        >(
            system_time.time_since_epoch()
        ).count();
    }

    auto scan_schematics(
        const fs::path& directory
    ) -> std::vector<SchematicRecord>
    {
        std::vector<SchematicRecord> records;
        std::error_code error;

        fs::create_directories(directory, error);

        if (error)
        {
            Output::send<LogLevel::Error>(
                STR("[PalSchematicaFilesystem] Unable to create directory: {}\n"),
                directory.wstring()
            );

            return records;
        }

        for (
            const auto& entry :
            fs::directory_iterator(directory, error)
        )
        {
            if (error)
            {
                break;
            }

            if (!entry.is_regular_file(error))
            {
                continue;
            }

            auto extension =
                entry.path().extension().wstring();

            std::transform(
                extension.begin(),
                extension.end(),
                extension.begin(),
                ::towlower
            );

            if (extension != L".palschem")
            {
                continue;
            }

            SchematicRecord record;
            record.file =
                wide_to_utf8(
                    entry.path()
                        .filename()
                        .wstring()
                );
            record.size =
                entry.file_size(error);

            if (error)
            {
                error.clear();
                record.size = 0;
            }

            const auto write_time =
                entry.last_write_time(error);

            if (!error)
            {
                record.modified_at =
                    file_time_to_unix_seconds(
                        write_time
                    );
            }
            else
            {
                error.clear();
                record.modified_at = 0;
            }

            records.emplace_back(
                std::move(record)
            );
        }

        std::sort(
            records.begin(),
            records.end(),
            [](
                const SchematicRecord& left,
                const SchematicRecord& right
            )
            {
                return left.file < right.file;
            }
        );

        return records;
    }

    auto write_manifest(
        const fs::path& directory,
        const std::vector<SchematicRecord>& records
    ) -> bool
    {
        const auto manifest_path =
            directory / L"library.palschemlib";

        const auto temporary_path =
            directory / L"library.palschemlib.tmp";

        std::ofstream output(
            temporary_path,
            std::ios::binary
            | std::ios::trunc
        );

        if (!output)
        {
            return false;
        }

        const auto now =
            std::chrono::duration_cast<
                std::chrono::seconds
            >(
                std::chrono::system_clock::now()
                    .time_since_epoch()
            ).count();

        output << "{\n";
        output << "  \"format\": \"PalSchematicaLibrary\",\n";
        output << "  \"formatVersion\": 1,\n";
        output << "  \"generatedAt\": " << now << ",\n";
        output << "  \"schematicCount\": "
               << records.size()
               << ",\n";

        if (!records.empty())
        {
            output
                << "  \"selectedFile\": \""
                << escape_json(records.front().file)
                << "\",\n";
        }
        else
        {
            output
                << "  \"selectedFile\": null,\n";
        }

        output << "  \"schematics\": [\n";

        for (
            std::size_t index = 0;
            index < records.size();
            ++index
        )
        {
            const auto& record = records[index];

            output << "    {\n";
            output
                << "      \"file\": \""
                << escape_json(record.file)
                << "\",\n";
            output
                << "      \"size\": "
                << record.size
                << ",\n";
            output
                << "      \"modifiedAt\": "
                << record.modified_at
                << "\n";
            output << "    }";

            if (index + 1 < records.size())
            {
                output << ",";
            }

            output << "\n";
        }

        output << "  ]\n";
        output << "}\n";
        output.close();

        if (!output)
        {
            return false;
        }

        std::error_code error;
        fs::remove(manifest_path, error);
        error.clear();

        fs::rename(
            temporary_path,
            manifest_path,
            error
        );

        return !error;
    }
}

class PalSchematicaFilesystemMod final :
    public RC::CppUserModBase
{
private:
    fs::path m_directory{};
    std::chrono::steady_clock::time_point
        m_next_scan{};
    std::string m_last_signature{};

    auto calculate_signature(
        const std::vector<SchematicRecord>& records
    ) const -> std::string
    {
        std::ostringstream signature;

        for (const auto& record : records)
        {
            signature
                << record.file
                << '\0'
                << record.size
                << '\0'
                << record.modified_at
                << '\0';
        }

        return signature.str();
    }

    auto refresh_manifest(
        const bool force
    ) -> void
    {
        const auto records =
            scan_schematics(m_directory);

        const auto signature =
            calculate_signature(records);

        if (!force && signature == m_last_signature)
        {
            return;
        }

        if (!write_manifest(
            m_directory,
            records
        ))
        {
            Output::send<LogLevel::Error>(
                STR("[PalSchematicaFilesystem] Failed to write manifest\n")
            );
            return;
        }

        m_last_signature = signature;

        Output::send<LogLevel::Verbose>(
            STR("[PalSchematicaFilesystem] Manifest refreshed: {} schematic(s) | {}\n"),
            records.size(),
            m_directory.wstring()
        );
    }

public:
    PalSchematicaFilesystemMod()
        : CppUserModBase()
    {
        ModName =
            STR("PalSchematicaFilesystem");
        ModVersion = STR("0.1.0");
        ModDescription =
            STR("Filesystem manifest helper for PalSchematica");
        ModAuthors = STR("Elias / OpenAI");

        m_directory =
            schematics_directory();

        m_next_scan =
            std::chrono::steady_clock::now();

        Output::send<LogLevel::Verbose>(
            STR("[PalSchematicaFilesystem] Helper loaded\n")
        );

        Output::send<LogLevel::Verbose>(
            STR("[PalSchematicaFilesystem] Schematics directory: {}\n"),
            m_directory.wstring()
        );

        refresh_manifest(true);
    }

    auto on_update() -> void override
    {
        const auto now =
            std::chrono::steady_clock::now();

        if (now < m_next_scan)
        {
            return;
        }

        m_next_scan =
            now + std::chrono::seconds{2};

        refresh_manifest(false);
    }
};

#define PALSCHEMATICA_FILESYSTEM_API __declspec(dllexport)

extern "C"
{
    PALSCHEMATICA_FILESYSTEM_API
    RC::CppUserModBase* start_mod()
    {
        return new PalSchematicaFilesystemMod();
    }

    PALSCHEMATICA_FILESYSTEM_API
    void uninstall_mod(
        RC::CppUserModBase* mod
    )
    {
        delete mod;
    }
}
