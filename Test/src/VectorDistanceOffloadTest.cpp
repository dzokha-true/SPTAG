// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "inc/Core/SPANN/VectorDistanceOffload.h"
#include "inc/Test.h"

#include <cstdlib>
#include <string>
#include <vector>

using SPTAG::ErrorCode;

namespace
{

class EnvGuard
{
  public:
    EnvGuard()
    {
        const char* value = std::getenv("SPTAG_AS_VECTOR_DISTANCE");
        if (value != nullptr)
        {
            m_hadValue = true;
            m_value = value;
        }
    }

    ~EnvGuard()
    {
        if (m_hadValue)
        {
            Set(m_value.c_str());
        }
        else
        {
            Unset();
        }
    }

    static void Set(const char* value)
    {
#ifdef _MSC_VER
        _putenv_s("SPTAG_AS_VECTOR_DISTANCE", value);
#else
        setenv("SPTAG_AS_VECTOR_DISTANCE", value, 1);
#endif
    }

    static void Unset()
    {
#ifdef _MSC_VER
        _putenv_s("SPTAG_AS_VECTOR_DISTANCE", "");
#else
        unsetenv("SPTAG_AS_VECTOR_DISTANCE");
#endif
    }

  private:
    bool m_hadValue = false;
    std::string m_value;
};

class FakeKeyValueIO : public SPTAG::Helper::KeyValueIO
{
  public:
    ErrorCode vectorDistanceReturn = ErrorCode::Success;
    std::vector<SPTAG::Helper::VectorDistanceResult> vectorDistanceResults;
    std::vector<SPTAG::Helper::VectorDistanceKeyStatus> keyStatuses;
    int vectorDistanceCalls = 0;
    int multiGetPageCalls = 0;
    std::vector<SPTAG::SizeType> observedHeads;
    std::uint16_t observedQuerySize = 0;
    std::uint32_t observedTopK = 0;

    void ShutDown() override {}

    ErrorCode Get(const SPTAG::SizeType, std::string*, const std::chrono::microseconds&,
                  std::vector<SPTAG::Helper::AsyncReadRequest>*) override
    {
        return ErrorCode::Undefined;
    }

    ErrorCode MultiGet(const std::vector<SPTAG::SizeType>&,
                       std::vector<SPTAG::Helper::PageBuffer<std::uint8_t>>&,
                       const std::chrono::microseconds&,
                       std::vector<SPTAG::Helper::AsyncReadRequest>*) override
    {
        ++multiGetPageCalls;
        return ErrorCode::Success;
    }

    ErrorCode MultiGet(const std::vector<SPTAG::SizeType>&, std::vector<std::string>*,
                       const std::chrono::microseconds&,
                       std::vector<SPTAG::Helper::AsyncReadRequest>*) override
    {
        return ErrorCode::Success;
    }

    ErrorCode VectorDistance(const std::vector<SPTAG::SizeType>& headIDs, const void*, std::uint16_t querySize,
                             std::uint32_t topK,
                             std::vector<SPTAG::Helper::VectorDistanceResult>* results,
                             std::vector<SPTAG::Helper::VectorDistanceKeyStatus>* statuses,
                             const std::chrono::microseconds&,
                             std::vector<SPTAG::Helper::AsyncReadRequest>*) override
    {
        ++vectorDistanceCalls;
        observedHeads = headIDs;
        observedQuerySize = querySize;
        observedTopK = topK;
        if (results != nullptr)
        {
            *results = vectorDistanceResults;
        }
        if (statuses != nullptr)
        {
            *statuses = keyStatuses;
        }
        return vectorDistanceReturn;
    }

    ErrorCode Put(const SPTAG::SizeType, const std::string&, const std::chrono::microseconds&,
                  std::vector<SPTAG::Helper::AsyncReadRequest>*) override
    {
        return ErrorCode::Success;
    }

    ErrorCode Merge(const SPTAG::SizeType, const std::string&, const std::chrono::microseconds&,
                    std::vector<SPTAG::Helper::AsyncReadRequest>*,
                    std::function<bool(const void*, const int)>) override
    {
        return ErrorCode::Success;
    }

    ErrorCode Delete(SPTAG::SizeType) override
    {
        return ErrorCode::Success;
    }

    bool Available() override
    {
        return true;
    }
};

class DefaultVectorDistanceIO : public FakeKeyValueIO
{
  public:
    ErrorCode VectorDistance(const std::vector<SPTAG::SizeType>&, const void*, std::uint16_t,
                             std::uint32_t,
                             std::vector<SPTAG::Helper::VectorDistanceResult>*,
                             std::vector<SPTAG::Helper::VectorDistanceKeyStatus>*,
                             const std::chrono::microseconds&,
                             std::vector<SPTAG::Helper::AsyncReadRequest>*) override
    {
        return SPTAG::Helper::KeyValueIO::VectorDistance({}, nullptr, 0, 0, nullptr, nullptr,
                                                        SPTAG::MaxTimeout, nullptr);
    }
};

struct FakeStats
{
    int m_totalListElementsCount = 0;
    int m_diskIOCount = 0;
    int m_diskAccessCount = 0;
    double m_compLatency = 0;
    double m_diskReadLatency = 0;
};

void InitializeVersionMap(SPTAG::COMMON::VersionLabel* versionMap)
{
    versionMap->Initialize(16, 16, 16);
    for (SPTAG::SizeType i = 0; i < 16; ++i)
    {
        versionMap->SetVersion(i, 1);
    }
}

void InitializeDeduper(SPTAG::COMMON::OptHashPosVector* deduper)
{
    deduper->Init(64, 4);
}

bool HasVID(const SPTAG::COMMON::QueryResultSet<float>& results, SPTAG::SizeType vid)
{
    for (int i = 0; i < results.GetResultNum(); ++i)
    {
        if (results.GetResult(i)->VID == vid)
        {
            return true;
        }
    }
    return false;
}

} // namespace

BOOST_AUTO_TEST_SUITE(VectorDistanceOffloadTest)

BOOST_AUTO_TEST_CASE(FlagPrecedence)
{
    EnvGuard guard;
    EnvGuard::Unset();

    BOOST_CHECK(!SPTAG::SPANN::VectorDistanceOffload::ResolveEnabled(false));
    BOOST_CHECK(SPTAG::SPANN::VectorDistanceOffload::ResolveEnabled(true));

    EnvGuard::Set("yes");
    BOOST_CHECK(SPTAG::SPANN::VectorDistanceOffload::ResolveEnabled(false));

    EnvGuard::Set("OFF");
    BOOST_CHECK(!SPTAG::SPANN::VectorDistanceOffload::ResolveEnabled(true));
}

BOOST_AUTO_TEST_CASE(BuildSupportReflectsCompileDefinition)
{
#ifdef SPTAG_HAS_AEROSPIKE_VECTOR_DISTANCE
    BOOST_CHECK(SPTAG::SPANN::VectorDistanceOffload::BuildSupportsVectorDistance());
#else
    BOOST_CHECK(!SPTAG::SPANN::VectorDistanceOffload::BuildSupportsVectorDistance());
#endif
}

BOOST_AUTO_TEST_CASE(OnlyNormalSearchUsesOffloadBranch)
{
    int truth = 0;
    int found = 0;
    BOOST_CHECK(!SPTAG::SPANN::VectorDistanceOffload::ShouldUse(false, nullptr, nullptr));
    BOOST_CHECK(SPTAG::SPANN::VectorDistanceOffload::ShouldUse(true, nullptr, nullptr));
    BOOST_CHECK(!SPTAG::SPANN::VectorDistanceOffload::ShouldUse(true, &truth, nullptr));
    BOOST_CHECK(!SPTAG::SPANN::VectorDistanceOffload::ShouldUse(true, nullptr, &found));
}

BOOST_AUTO_TEST_CASE(DefaultKeyValueIOVectorDistanceIsUndefined)
{
    DefaultVectorDistanceIO db;
    BOOST_CHECK(db.VectorDistance({}, nullptr, 0, 0, nullptr, nullptr, SPTAG::MaxTimeout, nullptr) ==
                ErrorCode::Undefined);
}

BOOST_AUTO_TEST_CASE(EnabledPathCallsVectorDistanceAndMergesHits)
{
    FakeKeyValueIO db;
    db.vectorDistanceResults = {
        {10, 2, 1, 0.2f},
        {11, 4, 1, 0.1f},
    };
    SPTAG::COMMON::VersionLabel versionMap;
    InitializeVersionMap(&versionMap);
    std::vector<SPTAG::SizeType> headIDs = {10, 11};
    SPTAG::COMMON::OptHashPosVector deduper;
    InitializeDeduper(&deduper);
    float query[2] = {1.0f, 2.0f};
    SPTAG::COMMON::QueryResultSet<float> results(query, 3);
    results.Reset();
    FakeStats stats;

    auto ret = SPTAG::SPANN::VectorDistanceOffload::Run(&db, &versionMap, headIDs, &deduper, nullptr,
                                                        results, &stats, 2, SPTAG::MaxTimeout, false);

    BOOST_CHECK(ret == ErrorCode::Success);
    BOOST_CHECK_EQUAL(db.vectorDistanceCalls, 1);
    BOOST_CHECK_EQUAL(db.multiGetPageCalls, 0);
    BOOST_CHECK_EQUAL(db.observedQuerySize, sizeof(query));
    BOOST_CHECK_EQUAL(db.observedTopK, 3);
    BOOST_CHECK_EQUAL(db.observedHeads.size(), 2);
    BOOST_CHECK(HasVID(results, 2));
    BOOST_CHECK(HasVID(results, 4));
    BOOST_CHECK_EQUAL(results.GetScanned(), 2);
    BOOST_CHECK_EQUAL(stats.m_totalListElementsCount, 2);
}

BOOST_AUTO_TEST_CASE(FiltersDeletedVersionMismatchDuplicateAndOutOfRangeHits)
{
    FakeKeyValueIO db;
    db.vectorDistanceResults = {
        {10, 2, 1, 0.2f},
        {10, 3, 9, 0.1f},
        {10, 4, 1, 0.05f},
        {10, 5, 1, 0.03f},
        {10, 99, 1, 0.01f},
        {10, 2, 1, 0.15f},
    };
    SPTAG::COMMON::VersionLabel versionMap;
    InitializeVersionMap(&versionMap);
    versionMap.Delete(4);
    std::vector<SPTAG::SizeType> headIDs = {10, 11};
    SPTAG::COMMON::OptHashPosVector deduper;
    InitializeDeduper(&deduper);
    deduper.CheckAndSet(5);
    float query[2] = {1.0f, 2.0f};
    SPTAG::COMMON::QueryResultSet<float> results(query, 4);
    results.Reset();

    auto ret = SPTAG::SPANN::VectorDistanceOffload::Run(&db, &versionMap, headIDs, &deduper, nullptr,
                                                        results, static_cast<FakeStats*>(nullptr), 2,
                                                        SPTAG::MaxTimeout, false);

    BOOST_CHECK(ret == ErrorCode::Success);
    BOOST_CHECK(HasVID(results, 2));
    BOOST_CHECK(!HasVID(results, 3));
    BOOST_CHECK(!HasVID(results, 4));
    BOOST_CHECK(!HasVID(results, 5));
    BOOST_CHECK(!HasVID(results, 99));
    BOOST_CHECK_EQUAL(results.GetScanned(), 6);
}

BOOST_AUTO_TEST_CASE(NonzeroKeyStatusFailsFast)
{
    FakeKeyValueIO db;
    db.keyStatuses = {{10, 2}};
    SPTAG::COMMON::VersionLabel versionMap;
    InitializeVersionMap(&versionMap);
    std::vector<SPTAG::SizeType> headIDs = {10, 11};
    SPTAG::COMMON::OptHashPosVector deduper;
    InitializeDeduper(&deduper);
    float query[2] = {1.0f, 2.0f};
    SPTAG::COMMON::QueryResultSet<float> results(query, 3);
    results.Reset();

    auto ret = SPTAG::SPANN::VectorDistanceOffload::Run(&db, &versionMap, headIDs, &deduper, nullptr,
                                                        results, static_cast<FakeStats*>(nullptr), 2,
                                                        SPTAG::MaxTimeout, false);

    BOOST_CHECK(ret == ErrorCode::DiskIOFail);
    BOOST_CHECK_EQUAL(db.vectorDistanceCalls, 1);
}

BOOST_AUTO_TEST_CASE(VectorApiErrorFailsFast)
{
    FakeKeyValueIO db;
    db.vectorDistanceReturn = ErrorCode::Fail;
    SPTAG::COMMON::VersionLabel versionMap;
    InitializeVersionMap(&versionMap);
    std::vector<SPTAG::SizeType> headIDs = {10, 11};
    SPTAG::COMMON::OptHashPosVector deduper;
    InitializeDeduper(&deduper);
    float query[2] = {1.0f, 2.0f};
    SPTAG::COMMON::QueryResultSet<float> results(query, 3);
    results.Reset();

    auto ret = SPTAG::SPANN::VectorDistanceOffload::Run(&db, &versionMap, headIDs, &deduper, nullptr,
                                                        results, static_cast<FakeStats*>(nullptr), 2,
                                                        SPTAG::MaxTimeout, false);

    BOOST_CHECK(ret == ErrorCode::DiskIOFail);
    BOOST_CHECK_EQUAL(db.vectorDistanceCalls, 1);
}

BOOST_AUTO_TEST_CASE(UnsupportedBuildFailsBeforeCallingVectorApi)
{
    FakeKeyValueIO db;
    SPTAG::COMMON::VersionLabel versionMap;
    InitializeVersionMap(&versionMap);
    std::vector<SPTAG::SizeType> headIDs = {10, 11};
    SPTAG::COMMON::OptHashPosVector deduper;
    InitializeDeduper(&deduper);
    float query[2] = {1.0f, 2.0f};
    SPTAG::COMMON::QueryResultSet<float> results(query, 3);
    results.Reset();

    auto ret = SPTAG::SPANN::VectorDistanceOffload::Run(&db, &versionMap, headIDs, &deduper, nullptr,
                                                        results, static_cast<FakeStats*>(nullptr), 2,
                                                        SPTAG::MaxTimeout, true);

    BOOST_CHECK(ret == ErrorCode::DiskIOFail);
    BOOST_CHECK_EQUAL(db.vectorDistanceCalls, 0);
}

BOOST_AUTO_TEST_SUITE_END()
