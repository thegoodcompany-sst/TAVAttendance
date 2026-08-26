package com.example.tavattendance.core

enum class SignedInDestination {
    Admin,
    Tutor,
    Parent,
    ArrivalStation,
}

fun signedInDestination(role: String?): SignedInDestination = when (role) {
    "admin" -> SignedInDestination.Admin
    "parent" -> SignedInDestination.Parent
    "arrival_station" -> SignedInDestination.ArrivalStation
    else -> SignedInDestination.Tutor
}
