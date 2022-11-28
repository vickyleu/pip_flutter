package com.example.pip_flutter

import android.content.Context
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DefaultBandwidthMeter
import com.google.android.exoplayer2.upstream.DefaultDataSource
import com.google.android.exoplayer2.upstream.FileDataSource
import com.google.android.exoplayer2.upstream.cache.CacheDataSink
import com.google.android.exoplayer2.upstream.cache.CacheDataSource

internal class CacheDataSourceFactory(
    private val context: Context,
    private val maxCacheSize: Long,
    private val maxFileSize: Long,
    upstreamDataSource: DataSource.Factory
) : DataSource.Factory {
    private val defaultDatasourceFactory: DefaultDataSource.Factory
    override fun createDataSource(): CacheDataSource {
        val pipFlutterPlayerCache = PipFlutterPlayerCache.createCache(context, maxCacheSize)
            ?: throw IllegalStateException("Cache can't be null.")

        return CacheDataSource(
            pipFlutterPlayerCache,
            defaultDatasourceFactory.createDataSource(),
            FileDataSource(),
            CacheDataSink(pipFlutterPlayerCache, maxFileSize),
            CacheDataSource.FLAG_BLOCK_ON_CACHE or CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR,
            null
        )
    }

    init {
        val bandwidthMeter = DefaultBandwidthMeter.Builder(context).build()
        defaultDatasourceFactory = DefaultDataSource.Factory(context, upstreamDataSource).apply {
            setTransferListener(bandwidthMeter)
        }
    }
}