package se.grenangen.audex.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import se.grenangen.audex.data.local.TokenManager
import se.grenangen.audex.data.local.TokenProvider
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class DataModule {

    @Binds
    @Singleton
    abstract fun bindTokenProvider(tokenManager: TokenManager): TokenProvider
}
