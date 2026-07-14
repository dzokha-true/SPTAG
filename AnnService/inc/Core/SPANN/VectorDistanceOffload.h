// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef _SPTAG_SPANN_VECTOR_DISTANCE_OFFLOAD_H_
#define _SPTAG_SPANN_VECTOR_DISTANCE_OFFLOAD_H_

#include "inc/Core/Common/VersionLabel.h"
#include "inc/Core/Common/QueryResultSet.h"
#include "inc/Core/Common/WorkSpace.h"
#include "inc/Helper/KeyValueIO.h"
#include "inc/Helper/Logging.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <limits>
#include <string>
#include <vector>

namespace SPTAG
{
namespace SPANN
{
namespace VectorDistanceOffload
{

inline bool TryParseBool(const char* value, bool* parsed)
{
    if (value == nullptr || parsed == nullptr)
    {
        return false;
    }

    std::string text(value);
    auto notSpace = [](unsigned char ch) { return !std::isspace(ch); };
    text.erase(text.begin(), std::find_if(text.begin(), text.end(), notSpace));
    text.erase(std::find_if(text.rbegin(), text.rend(), notSpace).base(), text.end());
    std::transform(text.begin(), text.end(), text.begin(),
                   [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });

    if (text == "1" || text == "true" || text == "yes" || text == "on")
    {
        *parsed = true;
        return true;
    }
    if (text == "0" || text == "false" || text == "no" || text == "off")
    {
        *parsed = false;
        return true;
    }
    return false;
}

inline bool ResolveEnabled(bool iniValue)
{
    const char* envValue = std::getenv("SPTAG_AS_VECTOR_DISTANCE");
    if (envValue == nullptr)
    {
        return iniValue;
    }

    bool parsed = false;
    if (TryParseBool(envValue, &parsed))
    {
        return parsed;
    }

    SPTAGLIB_LOG(Helper::LogLevel::LL_Error,
                 "Invalid SPTAG_AS_VECTOR_DISTANCE value '%s'; expected 1/true/yes/on or 0/false/no/off. Using INI value.\n",
                 envValue);
    return iniValue;
}

inline bool BuildSupportsVectorDistance()
{
#ifdef SPTAG_HAS_AEROSPIKE_VECTOR_DISTANCE
    return true;
#else
    return false;
#endif
}

inline bool ShouldUse(bool enabled, const void* truth, const void* found)
{
    return enabled && truth == nullptr && found == nullptr;
}

template<typename ValueType, typename StatsType>
ErrorCode Run(Helper::KeyValueIO* db,
              COMMON::VersionLabel* versionMap,
              const std::vector<SizeType>& headIDs,
              COMMON::OptHashPosVector* deduper,
              std::vector<Helper::AsyncReadRequest>* requests,
              COMMON::QueryResultSet<ValueType>& queryResults,
              StatsType* stats,
              DimensionType dim,
              const std::chrono::microseconds& timeout,
              bool unavailable)
{
    if (unavailable)
    {
        SPTAGLIB_LOG(Helper::LogLevel::LL_Error,
                     "VECTOR_DISTANCE offload enabled but Aerospike EC528 vector-distance API is unavailable.\n");
        return ErrorCode::DiskIOFail;
    }
    if (db == nullptr || versionMap == nullptr || deduper == nullptr || dim <= 0)
    {
        return ErrorCode::DiskIOFail;
    }
    if (queryResults.GetResultNum() <= 0 || headIDs.empty())
    {
        if (stats)
        {
            stats->m_compLatency = 0;
            stats->m_diskReadLatency = 0;
            stats->m_totalListElementsCount = 0;
            stats->m_diskIOCount = 0;
            stats->m_diskAccessCount = 0;
        }
        queryResults.SetScanned(0);
        return ErrorCode::Success;
    }

    const auto queryBytes = static_cast<std::size_t>(dim) * sizeof(ValueType);
    if (queryBytes > std::numeric_limits<std::uint16_t>::max())
    {
        SPTAGLIB_LOG(Helper::LogLevel::LL_Error,
                     "VECTOR_DISTANCE query too large: dim=%d bytes=%zu max=%u\n",
                     dim, queryBytes, static_cast<unsigned>(std::numeric_limits<std::uint16_t>::max()));
        return ErrorCode::DiskIOFail;
    }

    std::vector<Helper::VectorDistanceResult> scored;
    std::vector<Helper::VectorDistanceKeyStatus> keyStatuses;

    auto readStart = std::chrono::high_resolution_clock::now();
    ErrorCode ret = db->VectorDistance(headIDs,
                                       queryResults.GetQuantizedTarget(),
                                       static_cast<std::uint16_t>(queryBytes),
                                       static_cast<std::uint32_t>(queryResults.GetResultNum()),
                                       &scored,
                                       &keyStatuses,
                                       timeout,
                                       requests);
    auto readEnd = std::chrono::high_resolution_clock::now();
    double readLatency = static_cast<double>(
        std::chrono::duration_cast<std::chrono::microseconds>(readEnd - readStart).count());

    if (ret != ErrorCode::Success)
    {
        SPTAGLIB_LOG(Helper::LogLevel::LL_Error,
                     "VECTOR_DISTANCE offload request failed: code=%d heads=%zu\n",
                     static_cast<int>(ret), headIDs.size());
        return ErrorCode::DiskIOFail;
    }

    for (const auto& status : keyStatuses)
    {
        if (status.Status != 0)
        {
            SPTAGLIB_LOG(Helper::LogLevel::LL_Error,
                         "VECTOR_DISTANCE key status failed: head=%d status=%u\n",
                         status.HeadID, static_cast<unsigned>(status.Status));
            return ErrorCode::DiskIOFail;
        }
    }

    for (const auto& result : scored)
    {
        if (result.VID < 0 || static_cast<std::size_t>(result.VID) >= versionMap->Count())
        {
            continue;
        }
        if (versionMap->Deleted(result.VID))
        {
            continue;
        }
        if (versionMap->GetVersion(result.VID) != result.Version)
        {
            continue;
        }
        if (deduper->CheckAndSet(result.VID))
        {
            continue;
        }

        queryResults.AddPoint(result.VID, result.Distance);
    }

    if (stats)
    {
        stats->m_compLatency = 0;
        stats->m_diskReadLatency = readLatency / 1000;
        stats->m_totalListElementsCount = static_cast<int>(scored.size());
        stats->m_diskIOCount = 0;
        stats->m_diskAccessCount = 0;
    }
    queryResults.SetScanned(static_cast<int>(scored.size()));
    return ErrorCode::Success;
}

} // namespace VectorDistanceOffload
} // namespace SPANN
} // namespace SPTAG

#endif // _SPTAG_SPANN_VECTOR_DISTANCE_OFFLOAD_H_
