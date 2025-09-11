package your.package.util

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn

/**
 * Emits true when both:
 * 1) The device has an INTERNET-capable, VALIDATED network, and
 * 2) Firebase Realtime Database socket reports `.info/connected == true`.
 *
 * Requires INTERNET and ACCESS_NETWORK_STATE in the manifest.
 */
// Uncomment the next two lines if you use Hilt:
// @Singleton
// class NetworkMonitor @Inject constructor(@ApplicationContext context: Context)
class NetworkMonitor(context: Context) {

    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val infoRef = FirebaseDatabase.getInstance().reference.child(".info/connected")

    private fun createAndAttachFirebaseListener(emit: (Boolean) -> Unit): ValueEventListener {
        val listener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                emit(snapshot.getValue(Boolean::class.java) == true)
            }
            override fun onCancelled(error: DatabaseError) {
                emit(false)
            }
        }
        infoRef.addValueEventListener(listener)
        return listener
    }

    private fun detachFirebaseListener(listener: ValueEventListener?) {
        listener?.let(infoRef::removeEventListener)
    }

    private val upstream = callbackFlow {
        var fbListener: ValueEventListener? = null

        fun updateState() {
            if (isOnlineNow()) {
                if (fbListener == null) {
                    fbListener = createAndAttachFirebaseListener { trySend(it) }
                }
            } else {
                detachFirebaseListener(fbListener)
                fbListener = null
                trySend(false)
            }
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = updateState()
            override fun onCapabilitiesChanged(n: Network, caps: NetworkCapabilities) = updateState()
            override fun onLost(network: Network) = updateState()
            override fun onUnavailable() = updateState()
        }

        val req = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        // Initial state check
        updateState()

        connectivityManager.registerNetworkCallback(req, callback)

        awaitClose {
            connectivityManager.unregisterNetworkCallback(callback)
            detachFirebaseListener(fbListener)
        }
    }

    val isOnline: StateFlow<Boolean> = upstream
        .distinctUntilChanged()
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), false)

    private fun isOnlineNow(): Boolean {
        val n = connectivityManager.activeNetwork ?: return false
        val caps = connectivityManager.getNetworkCapabilities(n) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
               caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }
}
