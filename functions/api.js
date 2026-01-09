const mongoose = require('mongoose');
const nodemailer = require('nodemailer');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { S3Client, PutObjectCommand, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");

let cachedDb = null;

const connectDB = async () => {
    // Check if we already have a connection and if it's actually connected (1 = connected)
    if (mongoose.connection.readyState === 1) {
        console.log("DEBUG: Using existing MongoDB connection");
        return mongoose.connection;
    }

    // If a connection is currently being established, wait for it
    if (mongoose.connection.readyState === 2) {
        console.log("DEBUG: Connection in progress, waiting...");
        return mongoose.connection;
    }

    console.log("DEBUG: No active connection. Connecting to MongoDB...");
    mongoose.set('strictQuery', false);

    try {
        // Use a timeout to prevent the function from hanging indefinitely
        await mongoose.connect(process.env.MONGODB_URI, {
            serverSelectionTimeoutMS: 5000, 
            socketTimeoutMS: 45000,
        });

        console.log("DEBUG: MongoDB Connected Successfully");
        return mongoose.connection;
    } catch (error) {
        console.error("CRITICAL: MongoDB Connection Error:", error.message);
        throw error;
    }
};

// --- 1. INITIALIZE S3 CLIENT (IDrive e2) ---
const s3 = new S3Client({
    region: "us-west-1",
    endpoint: "https://s3.us-west-1.idrivee2.com", // Ensure https:// is here
    forcePathStyle: true, // <--- ADD THIS LINE
    credentials: {
        accessKeyId: process.env.E2_ACCESS_KEY,
        secretAccessKey: process.env.E2_SECRET_KEY,
    },
});

// --- 2. HELPER: SIGN PRIVATE URLS ---
// This turns a private key like "packages/123.jpg" into a temporary viewable link
async function getSecureUrl(objectKey) {
    if (!objectKey || objectKey.startsWith('http') || objectKey.startsWith('data:')) {
        return objectKey; 
    }
    try {
        const command = new GetObjectCommand({
            Bucket: process.env.E2_BUCKET_NAME,
            Key: objectKey,
        });
        // URL expires in 1 hour (3600 seconds)
        return await getSignedUrl(s3, command, { expiresIn: 3600 });
    } catch (err) {
        console.error("Signing Error:", err);
        return "";
    }
}

async function uploadToE2(base64String, identifier) {
    // 1. Check if string exists and is long enough to actually be an image
    if (!base64String || base64String.length < 100) {
        console.log("DEBUG: Image string too short or null");
        return "";
    }

    try {
        // 2. Extract raw data (Handle cases with or without the 'base64,' prefix)
        const base64Data = base64String.includes('base64,') 
            ? base64String.split('base64,')[1] 
            : base64String;

        const buffer = Buffer.from(base64Data, 'base64');
        const key = `packages/${Date.now()}_${identifier}.jpg`;

        // 3. Upload to IDrive e2
        await s3.send(new PutObjectCommand({
            Bucket: process.env.E2_BUCKET_NAME,
            Key: key,
            Body: buffer,
            ContentType: 'image/jpeg',
            // No ACL here keeps it private
        }));

        console.log("DEBUG: Upload Successful. Key:", key);
        return key; 
    } catch (err) {
        console.error("IDrive E2 Upload Error:", err);
        return "";
    }
}

// --- HELPER: DELETE OBJECT FROM IDRIVE E2 ---
async function deleteFromE2(objectKey) {
    if (!objectKey || objectKey.startsWith('http') || objectKey.startsWith('data:') || objectKey.startsWith('/9j/')) {
        return; // Don't try to delete URLs or Base64 strings
    }
    try {
        const { DeleteObjectCommand } = require("@aws-sdk/client-s3");
        await s3.send(new DeleteObjectCommand({
            Bucket: process.env.E2_BUCKET_NAME,
            Key: objectKey,
        }));
        console.log("DEBUG: Successfully deleted old image from IDrive:", objectKey);
    } catch (err) {
        console.error("IDrive E2 Delete Error:", err);
    }
}

// --- SCHEMAS ---
const userSchema = new mongoose.Schema({
    fullName: { type: String, required: true },
    email: { type: String, required: true, unique: true },
    phone: { type: String, required: true },
    gender: { 
        type: String, 
        enum: ['Male', 'Female', 'Other'], 
        required: true 
    }, // Added Gender
    dob: { type: String },
    occupation: { type: String },
    password: { type: String, required: true },
    profileImage: { type: String },
    address: {
        street: String,
        city: String,
        state: String,
        country: String
    },
    role: { 
        type: String, 
        enum: ['user', 'rider', 'admin'], 
        default: 'user'  // <--- THIS ENSURES ALL SIGNUPS ARE CLIENTS
    },
    isVerified: { type: Boolean, default: false },
    otp: { type: String },
    createdAt: { type: Date, default: Date.now }
});

const User = mongoose.model('User', userSchema);

const PackageSchema = new mongoose.Schema({
    senderName: String,
    status: { type: String, default: "received" },
    createdAt: { type: Date, default: Date.now }
});

const Package = mongoose.models.Package || mongoose.model('Package', PackageSchema);
// --- ORDER SCHEMA ---
const orderSchema = new mongoose.Schema({
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    userName: { type: String }, 
    userGender: { type: String, enum: ['Male', 'Female', 'Other'] }, 
    pickupLocation: { type: String, required: true },
    deliveryLocation: { type: String, required: true },
    pickupDate: { type: String, required: true },
    pickupTime: { type: String, required: true },
    deliveryDate: { type: String, required: true },
    deliveryTime: { type: String, required: true },
    receiverName: { type: String, required: true },
    receiverPhone: { type: String, required: true },
    weight: { type: String, required: false,  default: "" },
    packageImage: { type: String }, // Stores the IDrive e2 Key
    packageDescription: { type: String, required: true},    
    status: { 
        type: String, 
        enum: ['Pending', 'Accepted', 'Declined', 'In Transit', 'Delivered'], 
        default: 'Pending' 
    },
    createdAt: { type: Date, default: Date.now }
});

// SAFE DECLARATION (Prevents Netlify Crash)
const Order = mongoose.models.Order || mongoose.model('Order', orderSchema);

// --- MESSAGE SCHEMA ---
const messageSchema = new mongoose.Schema({
  senderEmail: { type: String, required: true },
  receiverEmail: { type: String, required: true },
  text: { type: String, required: true },
  packageImage: { type: String }, 
  isAdmin: { type: Boolean, default: false },
  status: { type: String, default: 'sent', enum: ['sent', 'read'] },
  orderId: { type: String, index: true }, 
  timestamp: { type: Date, default: Date.now }
});

// Compound Index: Optimizes fetching the LATEST messages for a specific order
messageSchema.index({ orderId: 1, timestamp: -1 });

const Message = mongoose.model('Message', messageSchema);
// --- HELPER: SEND OTP EMAIL ---
const sendOTPEmail = async (email, fullName, otp) => {
    console.log(`[DEBUG] Initializing Email Transporter for: ${email}`);
    
    const transporter = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 587, 
        secure: false, 
        auth: {
            user: process.env.GMAIL_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
        },
        tls: {
            rejectUnauthorized: false 
        }
    });

    try {
        // Verify connection configuration
        console.log("[DEBUG] Verifying SMTP connection...");
        await transporter.verify();
        console.log("[DEBUG] SMTP Connection verified successfully.");

        const logoUrl = "https://keahlogistics.netlify.app/assets/logo.png"; 

        const info = await transporter.sendMail({
            from: `"Keah Logistics" <${process.env.GMAIL_USER}>`,
            to: email,
            subject: "🔒 Verify Your Account - Keah Logistics",
            text: `Hello ${fullName}, your verification code is ${otp}.`,
            headers: {
                "X-Priority": "1 (Highest)",
                "X-MSMail-Priority": "High",
                "Importance": "High",
            },
            html: `
                <div style="background-color: #f4f7f9; padding: 40px 0; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;">
                    <table align="center" border="0" cellpadding="0" cellspacing="0" width="100%" style="max-width: 600px; background-color: #ffffff; border-radius: 20px; overflow: hidden; box-shadow: 0 4px 10px rgba(0,0,0,0.1);">
                        <tr>
                            <td bgcolor="#1E3C72" style="padding: 30px 20px; text-align: center;">
                                <img src="${logoUrl}" alt="Keah Logistics Logo" width="150" style="display: block; margin: 0 auto; filter: brightness(0) invert(1);">
                            </td>
                        </tr>
                        <tr>
                            <td style="padding: 40px 30px;">
                                <h2 style="color: #1E3C72; margin-top: 0; font-size: 24px; text-align: center;">Verify Your Email Address</h2>
                                <p style="color: #444444; font-size: 16px; line-height: 1.6; text-align: center;">
                                    Hello <strong>${fullName}</strong>,<br>
                                    Thank you for choosing Keah Logistics. To complete your registration and secure your account, please use the 6-digit verification code below:
                                </p>
                                <div style="margin: 30px 0; text-align: center;">
                                    <div style="display: inline-block; background-color: #f0f4f8; padding: 15px 40px; border-radius: 12px; border: 2px dashed #1E3C72;">
                                        <span style="font-size: 36px; font-weight: bold; color: #1E3C72; letter-spacing: 10px;">${otp}</span>
                                    </div>
                                </div>
                                <p style="color: #888888; font-size: 14px; text-align: center; margin-bottom: 0;">
                                    This code is valid for 10 minutes. <br>
                                    If you didn't request this, you can safely ignore this email.
                                </p>
                            </td>
                        </tr>
                        <tr>
                            <td style="padding: 20px 30px; background-color: #f9fafb; text-align: center; border-top: 1px solid #eeeeee;">
                                <p style="color: #aaaaaa; font-size: 12px; margin: 0;">
                                    &copy; 2026 Keah Logistics & Services. All rights reserved.<br>
                                    Lagos, Nigeria.
                                </p>
                            </td>
                        </tr>
                    </table>
                </div>
            `
        });

        console.log(`[DEBUG] Email sent successfully! MessageID: ${info.messageId}`);
        return info;

    } catch (error) {
        console.error("[ERROR] sendOTPEmail failed details:");
        console.error(`- Message: ${error.message}`);
        console.error(`- Code: ${error.code}`);
        console.error(`- Command: ${error.command}`);
        throw error; // Re-throw so the route catch block can handle it
    }
};

// --- HELPER: SEND WELCOME EMAIL ---
const sendWelcomeEmail = async (email, fullName, role = "user") => {
    if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
        console.warn("Email credentials missing, skipping email.");
        return;
    }

    try {
      const transporter = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 587, // Switch to 587
        secure: false, // Must be false for 587
        auth: {
            user: process.env.GMAIL_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
        },
        tls: {
            rejectUnauthorized: false // Helps prevent local/cloud cert issues
        }
    });
        const logoUrl = "https://keahlogistics.netlify.app/assets/logo.png"; 
        const subject = role === 'rider' ? 'Keah Logistics: Rider Account Created' : 'Welcome to Keah Logistics!';
        
        const welcomeText = role === 'rider' 
            ? `Your Rider Agent account has been successfully created by the Keah Logistics & Services. You can now log in using the credentials provided to you and start managing deliveries.` 
            : `We are excited to have you on board! Keah Logistics & Services provides seamless delivery solutions tailored just for you.`;

        await transporter.sendMail({
            from: `"Keah Logistics" <${process.env.GMAIL_USER}>`,
            to: email,
            subject: subject,
            headers: {
            "X-Priority": "1 (Highest)",
            "X-MSMail-Priority": "High",
            "Importance": "High",
        },
            html: `
            <div style="background-color: #f4f4f4; padding: 20px; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;">
                <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 10px rgba(0,0,0,0.1);">
                    
                    <div style="background-color: #0D1B2A; padding: 30px; text-align: center;">
                        <img src="${logoUrl}" alt="Keah Logistics Logo" style="width: 150px; margin-bottom: 10px;">
                        <div style="color: #FFD700; font-size: 14px; font-weight: bold; letter-spacing: 2px;">LOGISTICS & SERVICES</div>
                    </div>

                    <div style="padding: 40px; text-align: center;">
                        <h1 style="color: #0D1B2A; font-size: 24px;">Hello, ${fullName}!</h1>
                        <p style="color: #555; line-height: 1.6; font-size: 16px;">
                            ${welcomeText}
                        </p>
                        <p style="color: #555; font-size: 16px;">Your account is now <strong>Active</strong>.</p>
                        
                        <div style="margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px;">
                            <p style="color: #888; font-size: 14px;">Please keep your login details secure.</p>
                        </div>
                    </div>

                    <div style="background-color: #f9f9f9; padding: 20px; text-align: center; border-top: 1px solid #eee;">
                        <p style="color: #999; font-size: 12px; margin: 0;">
                            &copy; 2026 Keah Logistics & Services. All Rights Reserved.
                        </p>
                        <p style="color: #999; font-size: 12px; margin: 5px 0 0 0;">
                            Lagos, Nigeria.
                        </p>
                    </div>
                </div>
            </div>
            `
        });
    } catch (err) {
        console.error("Email error:", err);
    }
};

async function sendAdminOrderNotification(adminEmail, clientName, orderDetails) {
    // 1. CRITICAL: Validate environment variables before proceeding
    if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
        console.error("CRITICAL ERROR: GMAIL_USER or GMAIL_APP_PASSWORD is not defined in Netlify environment variables.");
        throw new Error("Email credentials missing for PLAIN authentication");
    }

    // 2. Configure Transporter with robust settings
    const transporter = nodemailer.createTransport({
        service: 'gmail',
        host: 'smtp.gmail.com',
        port: 465,
        secure: true, // Use SSL for port 465
        auth: {
            user: process.env.GMAIL_USER,
            pass: process.env.GMAIL_APP_PASSWORD, // Ensure this is a 16-character App Password
        },
    });

    // Helper to format ISO Date strings to readable text
    const formatDate = (dateStr) => {
        if (!dateStr) return "N/A";
        const d = new Date(dateStr);
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    };

    const logoUrl = "https://keahlogistics.netlify.app/assets/logo.png"; 

    const mailOptions = {
        from: `"Keah Logistics System" <${process.env.GMAIL_USER}>`,
        to: process.env.ADMIN_EMAIL,
        subject: `🚨 NEW ORDER: ${clientName} (${orderDetails.weight}kg)`,
        html: `
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                @media only screen and (max-width: 600px) {
                    .container { width: 100% !important; }
                    .content { padding: 25px !important; }
                }
            </style>
        </head>
        <body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;">
            <table border="0" cellpadding="0" cellspacing="0" width="100%">
                <tr>
                    <td align="center" style="padding: 20px 0;">
                        <table class="container" border="0" cellpadding="0" cellspacing="0" width="600" style="background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 10px rgba(0,0,0,0.1);">
                            <tr>
                                <td align="center" style="background-color: #0D1B2A; padding: 30px;">
                                    <img src="${logoUrl}" alt="Keah Logistics Logo" width="150" style="display: block; border: 0;">
                                    <div style="color: #FFD700; font-size: 12px; font-weight: bold; letter-spacing: 2px; margin-top: 10px; text-transform: uppercase;">Admin Order Alert</div>
                                </td>
                            </tr>
                            <tr>
                                <td class="content" style="padding: 40px; color: #333333;">
                                    <h2 style="margin: 0 0 10px 0; font-size: 22px; color: #0D1B2A; text-align: center;">New Delivery Request</h2>
                                    <p style="margin: 0 0 25px 0; font-size: 16px; line-height: 1.6; color: #555555; text-align: center;">
                                        Client <strong>${clientName}</strong> has just requested a rider. Review the logistics details below to proceed.
                                    </p>
                                    <table border="0" cellpadding="15" cellspacing="0" width="100%" style="background-color: #f9f9f9; border-radius: 8px; border-left: 4px solid #FFD700;">
                                        <tr>
                                            <td>
                                                <div style="color: #999; text-transform: uppercase; font-size: 10px; font-weight: bold; letter-spacing: 1px;">Pickup From</div>
                                                <div style="margin-top: 4px; font-size: 15px; font-weight: bold; color: #0D1B2A;">${orderDetails.pickupLocation}</div>
                                                <div style="font-size: 13px; color: #666;">Scheduled: ${formatDate(orderDetails.pickupDate)} @ ${orderDetails.pickupTime}</div>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="border-top: 1px solid #eeeeee;">
                                                <div style="color: #999; text-transform: uppercase; font-size: 10px; font-weight: bold; letter-spacing: 1px;">Delivery To</div>
                                                <div style="margin-top: 4px; font-size: 15px; font-weight: bold; color: #0D1B2A;">${orderDetails.deliveryLocation}</div>
                                                <div style="font-size: 13px; color: #666;">Expected: ${formatDate(orderDetails.deliveryDate)} @ ${orderDetails.deliveryTime}</div>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="border-top: 1px solid #eeeeee;">
                                                <div style="color: #999; text-transform: uppercase; font-size: 10px; font-weight: bold; letter-spacing: 1px;">Package Weight</div>
                                                <div style="margin-top: 4px; font-size: 15px; font-weight: bold; color: #0D1B2A;">${orderDetails.weight} KG</div>
                                            </td>
                                        </tr>
                                    </table>
                                    <div style="margin-top: 30px; padding: 0 10px;">
                                        <h3 style="font-size: 16px; color: #0D1B2A; margin-bottom: 10px; border-bottom: 1px solid #eee; padding-bottom: 5px;">Receiver Contact</h3>
                                        <p style="margin: 0; font-size: 14px; color: #444;"><strong>Name:</strong> ${orderDetails.receiverName}</p>
                                        <p style="margin: 5px 0 0 0; font-size: 14px; color: #444;"><strong>Phone:</strong> ${orderDetails.receiverPhone}</p>
                                    </div>
                                    <table border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-top: 40px;">
                                        <tr>
                                            <td align="center">
                                                <a href="https://keahlogistics-admin.netlify.app" style="background-color: #0D1B2A; color: #FFD700; padding: 15px 35px; text-decoration: none; border-radius: 5px; font-weight: bold; font-size: 14px; display: inline-block; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">MANAGE ORDER</a>
                                            </td>
                                        </tr>
                                    </table>
                                </td>
                            </tr>
                            <tr>
                                <td style="background-color: #f9f9f9; padding: 25px; text-align: center; border-top: 1px solid #eeeeee;">
                                    <p style="color: #999; font-size: 12px; margin: 0;">
                                        &copy; 2026 Keah Logistics & Services. All Rights Reserved.
                                    </p>
                                    <p style="color: #999; font-size: 12px; margin: 5px 0 0 0;">
                                        Lagos, Nigeria.
                                    </p>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
        </body>
        </html>
        `,
    };

    // 3. Send email and log response
    try {
        const info = await transporter.sendMail(mailOptions);
        console.log(`DEBUG: Admin notification sent for order from ${clientName}. Response: ${info.response}`);
        return info;
    } catch (error) {
        console.error("DEBUG: Nodemailer failed inside sendAdminOrderNotification:", error.message);
        throw error; // Propagate the error so the main handler knows it failed
    }
}
async function processOrderImages(order) {
    const plainOrder = order.constructor.name === 'model' ? order.toObject() : order;
    
    // Sign the Package Image
    if (plainOrder.packageImage && !plainOrder.packageImage.startsWith('http')) {
        plainOrder.packageImage = await getSecureUrl(plainOrder.packageImage);
    }
    
    // Sign the Profile Image if user details are attached
    if (plainOrder.profileImage && !plainOrder.profileImage.startsWith('http')) {
        plainOrder.profileImage = await getSecureUrl(plainOrder.profileImage);
    }
    
    return plainOrder;
}

async function pushNotification(targetEmail, title, messageBody, senderEmail = "") {
    // 1. Validation - Ensure both the Key and App ID exist in Netlify Environment Variables
    if (!process.env.ONESIGNAL_REST_API_KEY || !process.env.ONESIGNAL_APP_ID || !targetEmail) {
        console.warn("OneSignal Config Missing (Key or AppID) or No Target Email");
        return null;
    }

    // Clean the email to ensure it matches the OneSignal External ID exactly
    const cleanTargetEmail = targetEmail.toLowerCase().trim();

    try {
        const response = await fetch("https://api.onesignal.com/notifications", {
            method: "POST",
            headers: {
                "Content-Type": "application/json; charset=utf-8",
                // MODIFIED: Added .trim() to resolve the "Access Denied" error from your logs
                "Authorization": `Basic ${process.env.ONESIGNAL_REST_API_KEY.trim()}`
            },
            body: JSON.stringify({
                app_id: process.env.ONESIGNAL_APP_ID,
                // TARGETING: Matches the "External ID" column in your OneSignal User Dashboard
                include_aliases: {
                    external_id: [cleanTargetEmail]
                },
                target_channel: "push", 
                
                // Content
                headings: { en: title },
                contents: { en: messageBody },
                
                // Android specific high-priority settings
                priority: 10,
                android_visibility: 1, // Shows on lock screen
                
                // Ensure you have created this channel in OneSignal Settings > Platforms > Google Android
                android_channel_id: "livechat_messages", 

                data: { 
                    type: "chat_alert", 
                    sender: senderEmail,
                    click_action: "FLUTTER_NOTIFICATION_CLICK"
                }
            })
        });

        const result = await response.json();
        
        if (result.errors) {
            console.error(`OneSignal reported errors for ${cleanTargetEmail}:`, result.errors);
        } else {
            console.log(`Notification successfully queued for ${cleanTargetEmail}:`, result);
        }
        
        return result;
    } catch (err) {
        console.error("OneSignal Push Network Error:", err.message);
        return null;
    }
}

exports.handler = async (event, context) => {
    // 1. Setup & Context
    context.callbackWaitsForEmptyEventLoop = false;
    const path = event.path;
    const method = event.httpMethod;

    console.log(`--- NEW REQUEST: ${method} ${path} ---`);

    // 2. Headers
    const headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
        "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
        "Content-Type": "application/json"
    };

    if (method === 'OPTIONS') {
        return { statusCode: 200, headers, body: '' };
    }

    try {
        await connectDB();
// --- PARSE BODY (Fixes the ReferenceError) ---
    let body = {};
    if (event.body) {
        try {
            body = JSON.parse(event.body);
        } catch (e) {
            console.error("JSON Parse Error:", e.message);
        }
    }
// --- 1. JWT & SECURITY MIDDLEWARE ---
let decodedUser = null;

// Routes that require a valid login (User OR Admin)
const protectedRoutes = [
    'user', 'update-profile', 'get-messages', 'get-all-messages', 
    'mark-read', 'send-message', 'create-order'
];

// Routes that specifically require ADMIN role
const adminOnlyRoutes = ['admin/stats', 'admin/users'];

const isProtected = protectedRoutes.some(route => path.includes(route));
const isAdminOnly = adminOnlyRoutes.some(route => path.includes(route));

if (isProtected || isAdminOnly) {
    const authHeader = event.headers.authorization || event.headers.Authorization;
    
    if (!authHeader) {
        return { statusCode: 401, headers, body: JSON.stringify({ error: "Access denied. Token missing." }) };
    }

    try {
        const token = authHeader.replace('Bearer ', '');
        decodedUser = jwt.verify(token, process.env.JWT_SECRET);
        event.user = decodedUser; // Attach user data to the event

        // STRICT ROLE CHECK for Admin-Only paths
        if (isAdminOnly && decodedUser.role.toLowerCase() !== 'admin') {
            console.warn(`Unauthorized Admin Access Attempt: ${decodedUser.email}`);
            return { 
                statusCode: 403, 
                headers, 
                body: JSON.stringify({ error: "Access Denied: Admin privileges required." }) 
            };
        }
    } catch (err) {
        console.error("JWT Error:", err.message);
        // Standardized "Session expired" message for your Flutter app to catch
        return { statusCode: 401, headers, body: JSON.stringify({ error: "Session expired." }) };
    }
}


// --- 2. ROUTE: ADMIN LOGIN ---
if (path.includes('admin-login') && method === 'POST') {
    const emailInput = body.email ? body.email.trim().toLowerCase() : "";
    const passwordInput = body.password ? body.password.trim() : "";

    if (!emailInput || !passwordInput) {
        return { statusCode: 400, headers, body: JSON.stringify({ error: "Credentials required" }) };
    }

    const user = await User.findOne({ email: emailInput });

    // Validate existence and role
    if (!user || user.role !== 'admin') {
        return { statusCode: 403, headers, body: JSON.stringify({ error: "Unauthorized: Admin access only." }) };
    }

    const isMatch = await bcrypt.compare(passwordInput, user.password);
    if (!isMatch) {
        return { statusCode: 401, headers, body: JSON.stringify({ error: "Invalid credentials." }) };
    }

    // Generate Token
    const token = jwt.sign(
        { id: user._id, email: user.email, role: user.role },
        process.env.JWT_SECRET,
        { expiresIn: '24h' }
    );

    return { 
        statusCode: 200, 
        headers, 
        body: JSON.stringify({ 
            token: token, 
            user: { 
                id: user._id, 
                fullName: user.fullName, 
                email: user.email, 
                role: user.role 
            } 
        }) 
    };
}

        // 1. ROUTE: MASTER ADMIN SIGNUP
        if (path.includes('admin-signup') && event.httpMethod === 'POST') {
            const adminExists = await User.findOne({ role: 'admin' });
            if (adminExists) {
                return { statusCode: 403, headers, body: JSON.stringify({ error: "Master Admin already registered." }) };
            }

            if (!body.adminSecretKey || body.adminSecretKey !== process.env.ADMIN_SECRET_KEY) {
                return { statusCode: 403, headers, body: JSON.stringify({ error: "Invalid Admin Secret Key" }) };
            }

            const hashedPassword = await bcrypt.hash(body.password, 10);
            const newAdmin = new User({ 
                fullName: body.fullName,
                email: body.email,
                password: hashedPassword,
                role: "admin" 
            });
            
            await newAdmin.save();
            return { statusCode: 201, headers, body: JSON.stringify({ message: "Master Admin created" }) };
        }


        // --- PRE-ROUTE SETUP: Parse Body Once ---

// --- 1. ROUTE: INITIATE SIGNUP (CLIENTS) ---
if (path.includes('signup') && !path.includes('admin') && event.httpMethod === 'POST') {
    const { email, fullName } = body;
    console.log("DEBUG: Signup request for:", email);

    try {
        const existingUser = await User.findOne({ email: email });
        if (existingUser) {
            console.warn("DEBUG: Email exists:", email);
            return { 
                statusCode: 400, 
                headers, 
                body: JSON.stringify({ error: "This email is already registered." }) 
            };
        }

        // Generate OTP and ensure it is a string
        const generatedOtp = Math.floor(100000 + Math.random() * 900000).toString();

        console.log("DEBUG: Sending OTP email...");
        await sendOTPEmail(email, fullName, generatedOtp);
        console.log("DEBUG: Email sent successfully.");

        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify({ 
                message: "OTP sent successfully!",
                otpCode: generatedOtp 
            }) 
        };
    } catch (error) {
        console.error("CRITICAL ERROR in Signup Route:", error.message);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ 
                error: "Failed to process signup.",
                details: error.message 
            }) 
        };
    }
}

// --- 2. ROUTE: VERIFY OTP & SAVE USER (WITH IDRIVE STORAGE) ---
if (path.includes('verify-otp') && event.httpMethod === 'POST') {
    const { email, otp, serverOtp, userData } = body;
    
    console.log(`DEBUG: Verification attempt for ${email}. Received: ${otp}, Expected: ${serverOtp}`);

    // 1. Validate OTP
    if (String(otp) !== String(serverOtp)) {
        return { 
            statusCode: 400, 
            headers, 
            body: JSON.stringify({ error: "Invalid verification code" }) 
        };
    }

    try {
        // 2. Check for duplicate email
        const duplicateCheck = await User.findOne({ email: email });
        if (duplicateCheck) {
            return { 
                statusCode: 400, 
                headers, 
                body: JSON.stringify({ error: "User already exists." }) 
            };
        }

        // 3. Find Master Admin for assignment
        const masterAdmin = await User.findOne({ role: 'admin' });

        // 4. IMAGE HANDLING: UPLOAD TO IDRIVE E2
        let finalImageKey = "";
        if (userData.profileImage) {
            const isBase64 = userData.profileImage.startsWith('data:') || userData.profileImage.startsWith('/9j/');
            
            if (isBase64) {
                console.log(`[SIGNUP] Uploading profile image for: ${email}`);
                // Use email prefix as temporary identifier for the filename
                const identifier = email.split('@')[0]; 
                const uploadedKey = await uploadToE2(userData.profileImage, identifier);
                
                if (uploadedKey) {
                    finalImageKey = uploadedKey;
                }
            } else {
                // If it's already a key (unexpected but safe), keep it
                finalImageKey = userData.profileImage;
            }
        }

        // 5. Hash Password
        const hashedPassword = await bcrypt.hash(userData.password, 10);

        // 6. Create the new user with IDrive Key
        const newUser = new User({ 
            fullName: userData.fullName,
            email: userData.email.toLowerCase(),
            phone: userData.phone,
            gender: userData.gender,
            password: hashedPassword,
            role: "user",
            assignedAdmin: masterAdmin ? masterAdmin._id : null,
            profileImage: finalImageKey, // SAVES THE KEY (e.g. "packages/123_test.jpg")
            dob: userData.dob,
            occupation: userData.occupation,
            address: userData.address,
            isVerified: true,
            createdAt: new Date()
        });

        await newUser.save();
        console.log(`DEBUG: User saved and image stored in IDrive: ${finalImageKey}`);

        // 7. Send Welcome Email
        try {
            await sendWelcomeEmail(newUser.email, newUser.fullName, newUser.role);
        } catch (eEmail) {
            console.error(`DEBUG: Welcome email failed:`, eEmail.message);
        }

        return { 
            statusCode: 201, 
            headers, 
            body: JSON.stringify({ 
                message: "Account verified and created successfully!",
                assignedToAdmin: !!masterAdmin,
                // We don't need to return the signed URL here as the app will 
                // usually redirect to login after signup
            }) 
        };

    } catch (err) {
        console.error(`DEBUG: Database Error during save for ${email}:`, err.message);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: "Registration failed during database save." }) 
        };
    }
}

// --- 3. ROUTE: RESEND OTP ---
if (path.includes('resend-otp') && event.httpMethod === 'POST') {
    const { email, fullName } = body;
    console.log(`DEBUG: Resending OTP to: ${email}`);
    const newOtp = Math.floor(100000 + Math.random() * 900000).toString();

    try {
        await sendOTPEmail(email, fullName, newOtp);
        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify({ 
                message: "A new code has been sent.",
                otpCode: newOtp 
            }) 
        };
    } catch (error) {
        console.error(`DEBUG: Resend failed for ${email}:`, error.message);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: "Failed to resend email." }) 
        };
    }
}
  
        // 3. ROUTE: CREATE RIDER AGENT
        if (path.includes('create-rider') && event.httpMethod === 'POST') {
            if (body.adminSecretKey !== process.env.ADMIN_SECRET_KEY) {
                return { statusCode: 401, headers, body: JSON.stringify({ error: "Unauthorized: Invalid Admin Secret Key" }) };
            }

            const existingRider = await User.findOne({ email: body.email });
            if (existingRider) {
                return { statusCode: 400, headers, body: JSON.stringify({ error: "Email already exists for another account." }) };
            }

            if (!body.password) {
                return { statusCode: 400, headers, body: JSON.stringify({ error: "Password is required for Rider registration." }) };
            }

            const masterAdmin = await User.findOne({ role: 'admin' });
            const hashedPassword = await bcrypt.hash(body.password, 10);

            const newRider = new User({
                fullName: body.fullName,
                email: body.email,
                password: hashedPassword,
                phone: body.phone,
                role: "rider",
                dob: body.dob,
                occupation: body.occupation,
                profileImage: body.riderImage, 
                address: body.address,
                assignedAdmin: masterAdmin?._id
            });

            await newRider.save();
            await sendWelcomeEmail(body.email, body.fullName, "rider");

            return { statusCode: 201, headers, body: JSON.stringify({ message: "Rider Agent created successfully" }) };
        }

       // --- ROUTE: ADMIN DASHBOARD STATS (OPTIMIZED & ENHANCED) ---
if (path.includes('admin/stats') && method === 'GET') {
    // 1. SAFE ROLE AUTHORIZATION
    // Ensures the function doesn't crash if event.user is undefined
    const isAdmin = event.user && event.user.role && event.user.role.toLowerCase() === 'admin';

    if (!isAdmin) {
        console.error(`[AUTH ERROR] Unauthorized stats access by: ${event.user?.email || 'Unknown'}`);
        return { 
            statusCode: 403, 
            headers, 
            body: JSON.stringify({ error: "Forbidden: Admin access only" }) 
        };
    }

    try {
        // Ensure connection is established
        await connectDB();

        // 2. PARALLEL EXECUTION (Includes Messages for Badge Support)
        const [
            userCount, 
            riderCount, 
            packageCount, 
            activeRequestsCount, 
            unreadMessagesCount
        ] = await Promise.all([
            User.countDocuments({ role: 'user' }),
            User.countDocuments({ role: 'rider' }),
            Package.countDocuments(),
            User.countDocuments({ isRequestingRider: true }),
            // Count messages sent by users (isAdmin: false) that are not yet "read"
            Message.countDocuments({ isAdmin: false, status: { $ne: 'read' } })
        ]);

        console.log(`[STATS] Dashboard update processed for Admin: ${event.user.email}`);

        // 3. ENHANCED RESPONSE BODY
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                totalUsers: userCount,
                activeRiders: riderCount,
                totalPackages: packageCount,
                activeRequests: activeRequestsCount,
                unreadMessages: unreadMessagesCount // Send this to your Flutter UI for the badge
            })
        };
    } catch (error) {
        console.error("Stats DB Error:", error.message);
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({ 
                error: "Internal Server Error", 
                details: error.message 
            })
        };
    }
}

        // --- NEW ROUTE: FETCH ALL RIDERS ---
// --- FETCH ALL RIDERS ---
if (path.includes('admin/riders') && event.httpMethod === 'GET') {
    try {
        // Fetching all fields for users with the 'rider' role
        // .lean() makes the query faster by returning plain JS objects
        const riders = await User.find({ role: 'rider' })
            .select('+password') // Only if you need to check password existence
            .sort({ createdAt: -1 })
            .lean();
        
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify(riders)
        };
    } catch (error) {
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({ error: "Failed to fetch riders" })
        };
    }
}

if (path.includes('update-rider') && event.httpMethod === 'PUT') {
    const id = path.split('/').pop();
    const updates = JSON.parse(event.body);

    // If password is being updated, hash it before saving
    if (updates.password) {
        const salt = await bcrypt.genSalt(10);
        updates.password = await bcrypt.hash(updates.password, salt);
    }

    const updatedRider = await User.findByIdAndUpdate(
        id, 
        { $set: updates }, 
        { new: true } // Returns the updated document
    );

    return {
        statusCode: 200,
        headers,
        body: JSON.stringify(updatedRider)
    };
}

// --- ROUTE: FETCH ALL REGULAR USERS WITH SECURE IMAGE URLS ---
if (path.endsWith('admin/users') && method === 'GET') {
    try {
        // 1. Role Check
        if (!event.user || event.user.role !== 'admin') {
            return { 
                statusCode: 403, 
                headers, 
                body: JSON.stringify({ error: "Unauthorized: Admin access only." }) 
            };
        }

        // 2. Fetch users
        const users = await User.find({ role: 'user' })
            .select('-password -__v -resetPasswordToken -resetPasswordExpires') 
            .sort({ createdAt: -1 })
            .lean(); // Use lean() for faster processing and to allow object mutation

        // 3. Generate Presigned URLs for Profile Images
        // Assuming you have an 's3' client and 'getSignedUrl' helper configured
        const usersWithImages = await Promise.all(users.map(async (user) => {
            if (user.profileImage && !user.profileImage.startsWith('http')) {
                try {
                    // This helper interacts with your IDrive e2 S3 bucket
                    user.profileImage = await getSecureUrl(user.profileImage);
                } catch (err) {
                    console.error(`Error signing URL for ${user._id}:`, err);
                    user.profileImage = null; // Fallback if signing fails
                }
            }
            return user;
        }));

        return { statusCode: 200, headers, body: JSON.stringify(usersWithImages) };

    } catch (error) {
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({ error: "Internal Server Error", details: error.message })
        };
    }
}

// --- ROUTE: DELETE USER (New - Matches your Flutter code) ---
if (path.includes('admin/delete-user/') && method === 'DELETE') {
    try {
        if (!event.user || event.user.role !== 'admin') {
            return { statusCode: 403, headers, body: JSON.stringify({ error: "Unauthorized" }) };
        }

        // Extract ID from path (e.g., .../delete-user/658af...)
        const userId = path.split('/').pop();

        const deletedUser = await User.findByIdAndDelete(userId);

        if (!deletedUser) {
            return { statusCode: 404, headers, body: JSON.stringify({ error: "User not found" }) };
        }

        console.log(`[ADMIN] User ${userId} deleted by ${event.user.email}`);
        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify({ message: "User successfully removed" }) 
        };

    } catch (error) {
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({ error: "Delete failed", details: error.message })
        };
    }
}
  // DELETE USER
  if (path.includes('admin/delete-user') && event.httpMethod === 'DELETE') {
            const userId = path.split('/').pop();
            await User.findByIdAndDelete(userId);
            return { statusCode: 200, headers, body: JSON.stringify({ message: "User deleted successfully" }) };
        }

// --- UPDATED ROUTE: UPDATE RIDER (PUT) ---
if (path.includes('update-rider') && event.httpMethod === 'PUT') {
    try {
        const id = path.split('/').pop();
        
        // 1. Prepare the update object
        let updateData = {
            fullName: body.fullName,
            phone: body.phone,
            profileImage: body.profileImage // This handles the new base64 string
        };

        // 2. Handle Password Change (If Admin provided one)
        if (body.password && body.password.trim() !== "") {
            const salt = await bcrypt.genSalt(10);
            updateData.password = await bcrypt.hash(body.password, salt);
        }

        // 3. Update Database
        const updatedUser = await User.findByIdAndUpdate(
            id, 
            { $set: updateData }, 
            { new: true }
        ).select('-password'); // Don't return the hashed password in the response

        if (!updatedUser) {
            return { 
                statusCode: 404, 
                headers, 
                body: JSON.stringify({ error: "Rider not found" }) 
            };
        }

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({ 
                message: "Rider updated successfully", 
                user: updatedUser 
            })
        };
    } catch (error) {
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: "Server error during update", details: error.message }) 
        };
    }

}

// --- STANDARD LOGIN (USER & RIDER) ---
if (path.includes('login') && event.httpMethod === 'POST') {
    const { email, password, requiredRole } = body; 

    // 1. Find the user
    const user = await User.findOne({ email: email.toLowerCase().trim() });
    
    // 2. Security: Don't let Admins log in through the User/Rider route
    if (!user || user.role === 'admin') {
        return { 
            statusCode: 404, 
            headers, 
            body: JSON.stringify({ error: "User account not found." }) 
        };
    }

    // 3. Verify Password
    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
        return { statusCode: 401, headers, body: JSON.stringify({ error: "Invalid credentials" }) };
    }

    // 4. Role Strictness (e.g., Rider trying to log into User app)
    if (requiredRole && user.role !== requiredRole) {
        return { 
            statusCode: 403, 
            headers, 
            body: JSON.stringify({ error: `Please use the Keah ${user.role} app to login.` }) 
        };
    }

    // 5. Verify Account
    if (!user.isVerified) {
        return { 
            statusCode: 401, 
            headers, 
            body: JSON.stringify({ 
                error: "Email not verified", 
                notVerified: true,
                user: { id: user._id, email: user.email }
            }) 
        };
    }

   const token = jwt.sign(
        { 
            id: user._id, 
            email: user.email, // MUST be here for Profile Security checks
            role: user.role 
        }, 
        process.env.JWT_SECRET, 
        { expiresIn: '30d' } 
    );

    return { 
        statusCode: 200, 
        headers, 
        body: JSON.stringify({ 
            message: "Login successful", 
            token, 
            user: { 
                id: user._id,
                fullName: user.fullName, 
                email: user.email, 
                role: user.role,
                profileImage: user.profileImage || "",
                phone: user.phone || ""
            } 
        }) 
    };
}
// --- 2. ROUTE: UPDATE PROFILE (SECURE + IDRIVE UPLOAD + CLEANUP) ---
if (path.includes('update-profile') && method === 'PUT') {
    const { fullName, phone, password, profileImage, dob, occupation, address, gender } = body;
    
    const rawEmail = body.email;
    if (!rawEmail) {
        return { statusCode: 400, headers, body: JSON.stringify({ error: "Email is required" }) };
    }
    const email = rawEmail.toLowerCase();

    if (!decodedUser || decodedUser.email !== email) {
        return { statusCode: 403, headers, body: JSON.stringify({ error: "Unauthorized access" }) };
    }

    const user = await User.findOne({ email });
    if (!user) {
        return { statusCode: 404, headers, body: JSON.stringify({ error: "User not found" }) };
    }

    const oldImageKey = user.profileImage;

    if (profileImage) {
        const isBase64 = profileImage.startsWith('data:') || profileImage.startsWith('/9j/');
        
        if (isBase64) {
            const newS3Key = await uploadToE2(profileImage, user._id.toString());
            if (newS3Key) {
                user.profileImage = newS3Key;
                // Delete old image if it was an S3 key
                if (oldImageKey && !oldImageKey.startsWith('data:') && !oldImageKey.startsWith('/9j/')) {
                    await deleteFromE2(oldImageKey);
                }
            }
        } else {
            user.profileImage = profileImage;
        }
    }

    user.fullName = fullName || user.fullName;
    user.phone = phone || user.phone;
    user.dob = dob || user.dob;
    user.occupation = occupation || user.occupation;
    user.gender = gender || user.gender;

    if (address) {
        user.address = {
            ...user.address,
            street: address.street || (user.address && user.address.street),
            city: address.city || (user.address && user.address.city),
            state: address.state || (user.address && user.address.state),
            country: address.country || (user.address && user.address.country || "Nigeria")
        };
    }

    if (password && password.length > 0) {
        const salt = await bcrypt.genSalt(10);
        user.password = await bcrypt.hash(password, salt);
    }

    await user.save();

    const displayImage = (user.profileImage && !user.profileImage.startsWith('http')) 
        ? await getSecureUrl(user.profileImage) 
        : user.profileImage;

    return { 
        statusCode: 200, 
        headers, 
        body: JSON.stringify({ 
            message: "Profile updated successfully",
            user: { ...user.toObject(), profileImage: displayImage }
        }) 
    };
}

// --- 3. ROUTE: GET USER DATA (SECURE + SIGNED IMAGE) ---
if (path.includes('user') && event.httpMethod === 'GET') {
    const emailParam = event.queryStringParameters ? event.queryStringParameters.email : null;

    if (!emailParam) {
        return { statusCode: 400, headers, body: JSON.stringify({ error: "Email parameter is required" }) };
    }

    const email = emailParam.toLowerCase();

    if (!event.user || event.user.email !== email) {
        return { statusCode: 403, headers, body: JSON.stringify({ error: "Forbidden" }) };
    }

    try {
        // Use .lean() to allow us to swap the profileImage key for a URL
        const user = await User.findOne({ email }).select("-password").lean();

        if (!user) {
            return { statusCode: 404, headers, body: JSON.stringify({ error: "User not found" }) };
        }

        // SIGN THE IMAGE URL
        if (user.profileImage && !user.profileImage.startsWith('http')) {
            user.profileImage = await getSecureUrl(user.profileImage);
        }

        return { statusCode: 200, headers, body: JSON.stringify(user) };
    } catch (dbError) {
        return { statusCode: 500, headers, body: JSON.stringify({ error: "Internal server error" }) };
    }
}

// --- 4. ROUTE: FETCH CLIENT ORDERS ---
if (path.includes('client-orders') && event.httpMethod === 'GET') {
    try {
        const clientId = event.queryStringParameters.clientId;
        if (!clientId) {
            return { statusCode: 400, headers, body: JSON.stringify({ error: "ClientId required" }) };
        }
        const orders = await Order.find({ clientId }).sort({ createdAt: -1 });
        return { statusCode: 200, headers, body: JSON.stringify(orders) };
    } catch (err) {
        return { statusCode: 500, headers, body: JSON.stringify({ error: err.message }) };
    }
}

// --- 2. ROUTE: SEND MESSAGE (With Presence Check) ---
if (path.includes('send-message') && method === 'POST') {
    let body;
    try {
        body = (typeof event.body === 'string') ? JSON.parse(event.body) : event.body;
    } catch (parseErr) {
        return { statusCode: 400, headers, body: JSON.stringify({ error: "Invalid JSON format" }) };
    }

    let verifiedSenderEmail;
    try {
        const authHeader = event.headers.authorization || event.headers.Authorization;
        const token = authHeader.split(' ')[1];
        const decoded = jwt.verify(token, process.env.JWT_SECRET); 
        verifiedSenderEmail = decoded.email.toLowerCase().trim();
    } catch (jwtErr) {
        return { statusCode: 401, headers, body: JSON.stringify({ error: "Unauthorized" }) };
    }

    const adminEmail = "keahlogisticsq@gmail.com";
    const isAdminFlag = verifiedSenderEmail === adminEmail;
    const senderEmail = verifiedSenderEmail;
    const receiverEmail = isAdminFlag ? (body.email || "").toLowerCase().trim() : adminEmail;

    try {
        await connectDB();

        // 1. Mark previous messages as READ (because sending a reply implies reading)
        await Message.updateMany(
            { senderEmail: receiverEmail, receiverEmail: senderEmail, status: { $ne: 'read' } },
            { $set: { status: 'read' } }
        );

        // --- THE LOGIC: INSTANT DOUBLE TICK CHECK ---
        // Check if receiver has been active in the last 60 seconds
        const oneMinuteAgo = new Date(Date.now() - 60000);
        const isReceiverOnline = await Message.findOne({
            $or: [{ senderEmail: receiverEmail }, { receiverEmail: receiverEmail }],
            timestamp: { $gte: oneMinuteAgo }
        });

        // 2. Handle Image
        let storageKey = "";
        if (body.packageImage && body.packageImage.length > 100) {
            const folderName = `chat_${(isAdminFlag ? receiverEmail : senderEmail).split('@')[0]}`;
            storageKey = await uploadToE2(body.packageImage, folderName);
        }

        // 3. Save New Message
        const messageData = {
            text: (body.text || "").trim() !== "" ? body.text : (storageKey ? "📷 Sent an image" : ""),
            isAdmin: isAdminFlag,
            packageImage: storageKey, 
            // If receiver is online, start as 'delivered' (Double Tick), else 'sent' (Single Tick)
            status: isReceiverOnline ? 'delivered' : 'sent', 
            senderEmail: senderEmail,
            receiverEmail: receiverEmail,
            timestamp: new Date()
        };

        const savedMessage = await new Message(messageData).save();

        // 4. Trigger Push Notification
        const notificationTitle = isAdminFlag ? "Keah Logistics 🚚" : "New Message Alert";
        await pushNotification(receiverEmail, notificationTitle, messageData.text, senderEmail);

        return { statusCode: 201, headers, body: JSON.stringify(savedMessage) };
    } catch (err) {
        return { statusCode: 500, headers, body: JSON.stringify({ error: err.message }) };
    }
}

// --- 4. ROUTE: CREATE ORDER + RIDER REQUEST (Optimized for Netlify) ---
if (path.includes('create-order') && method === 'POST') {
    let data;
    try {
        data = JSON.parse(event.body);
    } catch (e) {
        return { statusCode: 400, headers, body: JSON.stringify({ error: "Invalid JSON body" }) };
    }

    const { 
        pickupLocation, deliveryLocation, 
        pickupDate, pickupTime, deliveryDate, deliveryTime, 
        receiverName, receiverPhone, weight, 
        packageDescription, packageImage 
    } = data;

    // 1. JWT Safe Identification
    const cleanEmail = (event.user && event.user.email) ? event.user.email.toLowerCase().trim() : null;

    if (!deliveryDate || !deliveryTime || !cleanEmail || !packageDescription) {
        return { 
            statusCode: 400, 
            headers, 
            body: JSON.stringify({ error: "Missing required fields or unauthorized session." }) 
        };
    }

    try {
        await connectDB();
        const cleanAdminEmail = "keahlogisticsq@gmail.com";
        const now = new Date(); 
        
        const user = await User.findOne({ email: cleanEmail });
        if (!user) {
            return { statusCode: 404, headers, body: JSON.stringify({ error: "User not found." }) };
        }

        // --- MARK AS READ LOGIC ---
        await Message.updateMany(
            { 
                senderEmail: cleanAdminEmail, 
                receiverEmail: cleanEmail, 
                status: { $ne: 'read' } 
            },
            { $set: { status: 'read' } }
        );

        // 📸 2. HANDLE IDRIVE E2 UPLOAD (Returns the Private Key/Path)
        let storageKey = "";
        if (packageImage && packageImage.length > 50) {
            storageKey = await uploadToE2(packageImage, cleanEmail.split('@')[0]);
        }

        // 📝 3. PREPARE DATABASE OBJECTS
        const newOrder = new Order({
            userId: user._id,
            userName: user.fullName,
            userGender: user.gender,
            pickupLocation,
            deliveryLocation,
            pickupDate,
            pickupTime,
            deliveryDate, 
            deliveryTime, 
            receiverName,
            receiverPhone,
            weight: weight || "N/A", 
            packageDescription,
            packageImage: storageKey, // Store the iDrive Key
            status: "Pending",
            timestamp: now 
        });

        // Save Order first to obtain the _id for linking
        const savedOrder = await newOrder.save();

        const receiptText = `📦 **NEW ORDER LOGGED**\n\n📝 DESC: ${packageDescription}\n📍 FROM: ${pickupLocation}\n🗓️ Pickup: ${pickupDate} @ ${pickupTime}\n\n🏁 TO: ${deliveryLocation}\n\n👤 RECEIVER: ${receiverName}\n📞 CONTACT: ${receiverPhone}\n⚖️ WEIGHT: ${weight}kg\n\nStatus: Awaiting Dispatcher.`;

        // System Alert (Message from User to Admin) - Linked with orderId
        const systemAlert = new Message({
            senderEmail: cleanEmail,
            receiverEmail: cleanAdminEmail,
            text: receiptText,
            isAdmin: false,
            packageImage: storageKey,
            orderId: savedOrder._id, // Critical for tracking
            status: 'sent',
            timestamp: now
        });

        // Auto Reply (Message from Admin to User) - Linked with orderId
        const autoReply = new Message({
            senderEmail: cleanAdminEmail,
            receiverEmail: cleanEmail,
            text: `Hello ${user.fullName.split(' ')[0]}! 👋 We've received your order for "${packageDescription}". Keah Logistics will contact you shortly to confirm pickup.`,
            isAdmin: true,
            orderId: savedOrder._id, // Critical for tracking
            status: 'sent',
            timestamp: now
        });

        // ✨ Save messages simultaneously
        await Promise.all([
            systemAlert.save(),
            autoReply.save()
        ]);

        // 📧 4. NOTIFY ADMIN (Non-blocking notifications)
        try {
            // We don't await these strictly to speed up user response time
            Promise.all([
                sendAdminOrderNotification(process.env.ADMIN_EMAIL, user.fullName || cleanEmail, savedOrder),
                pushNotification(
                    cleanAdminEmail, 
                    "📦 New Order Alert", 
                    `${user.fullName || 'Customer'} placed an order: ${packageDescription}`,
                    cleanEmail
                )
            ]);
        } catch (notifyErr) {
            console.error("Notification Warning:", notifyErr.message);
        }

        return { 
            statusCode: 201, 
            headers, 
            body: JSON.stringify({ 
                message: "Order created successfully", 
                orderId: savedOrder._id,
                timestamp: now
            }) 
        };

    } catch (error) {
        console.error("Critical Backend Error:", error);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: "Internal Server Error", details: error.message }) 
        };
    }
}

// --- MARK MESSAGES AS READ (Protected by JWT) ---
if (path.includes('mark-read') && method === 'POST') {
    try {
        // 1. JWT Identification (Security)
        const authHeader = event.headers.authorization || event.headers.Authorization;
        if (!authHeader) return { statusCode: 401, headers, body: JSON.stringify({ error: "Unauthorized" }) };
        
        const token = authHeader.split(' ')[1];
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        const requesterEmail = decoded.email.toLowerCase().trim();

        await connectDB();
        const { email, isAdminSide } = JSON.parse(event.body);
        const targetEmail = email.toLowerCase().trim();

        let filter = {};

        if (isAdminSide === true) {
            // CASE 1: ADMIN IS LOGGED IN
            // The Admin is looking at messages SENT BY the User (targetEmail)
            // directed TO the Admin (requesterEmail).
            filter = { 
                senderEmail: targetEmail, 
                receiverEmail: requesterEmail, 
                status: { $ne: 'read' } 
            };
        } else {
            // CASE 2: USER IS LOGGED IN
            // The User is looking at messages SENT BY the Admin (targetEmail)
            // directed TO the User (requesterEmail).
            filter = { 
                senderEmail: targetEmail, 
                receiverEmail: requesterEmail, 
                status: { $ne: 'read' } 
            };
        }

        // Update all relevant messages to 'read'
        const result = await Message.updateMany(filter, { 
            $set: { 
                status: 'read',
                readAt: new Date() 
            } 
        });

        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify({ 
                success: true,
                message: "Messages marked as read", 
                modifiedCount: result.modifiedCount 
            }) 
        };
    } catch (error) {
        console.error("Mark Read Error:", error.message);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: error.message }) 
        };
    }
}

// --- 1. ROUTE: GET MESSAGES (With Auto-Delivery Status Sync) ---
if (path.includes('get-messages') && method === 'GET') {
    try {
        await connectDB();
        
        // 1. Identity from the verified JWT token (passed from your auth middleware)
        const requesterEmail = event.user.email.toLowerCase().trim();
        const requestedEmail = event.queryStringParameters ? event.queryStringParameters.email : null;
        const isAdmin = event.user.role.toLowerCase() === 'admin';

        let query = {};
        let targetUserEmail = "";

        if (isAdmin && requestedEmail) {
            // ADMIN VIEW: Fetching conversation with a specific customer
            targetUserEmail = requestedEmail.toLowerCase().trim();
            query = {
                $or: [
                    { senderEmail: targetUserEmail }, 
                    { receiverEmail: targetUserEmail }
                ]
            };
        } else {
            // USER VIEW: Fetching their own conversation with Admin
            targetUserEmail = requesterEmail;
            query = {
                $or: [
                    { senderEmail: targetUserEmail },
                    { receiverEmail: targetUserEmail }
                ]
            };
        }

        // --- NEW STATUS SYNC LOGIC ---
        // If I am fetching messages, any message sent TO me that is currently 'sent'
        // must now be marked 'delivered' because my app is fetching it right now.
        // This triggers the "Double Grey Tick" on the sender's screen.
        await Message.updateMany(
            { 
                receiverEmail: requesterEmail, 
                status: 'sent' 
            }, 
            { 
                $set: { status: 'delivered' } 
            }
        );

        // 2. Fetch messages - Limit to 50 latest
        const messages = await Message.find(query)
            .sort({ timestamp: -1 })
            .limit(50) 
            .lean();

        // 3. Generate Secure URLs for any images in the chat
        const signedMessages = await Promise.all(messages.map(async (msg) => {
            if (msg.packageImage && !msg.packageImage.startsWith('http') && !msg.packageImage.startsWith('data:')) {
                msg.packageImage = await getSecureUrl(msg.packageImage);
            }
            return msg;
        }));

        // Reverse for chronological chat order (Oldest at top, Newest at bottom)
        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify(signedMessages.reverse()) 
        };
    } catch (err) {
        console.error("Get Messages Error:", err);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: err.message }) 
        };
    }
}

// --- 2. ROUTE: ADMIN INBOX AGGREGATION ---
if (path.includes('get-all-messages') && method === 'GET') {
    // 1. SECURITY: Explicit check for Admin role from decoded JWT
    const isAdmin = event.user && event.user.role && event.user.role.toLowerCase() === 'admin';
    
    if (!isAdmin) {
        console.error(`[AUTH ERROR] Unauthorized attempt by: ${event.user?.email || 'Unknown'}`);
        return { 
            statusCode: 403, 
            headers, 
            body: JSON.stringify({ error: "Access Denied: Admin privileges required." }) 
        };
    }

    try {
        await connectDB();
        
        const chatThreads = await Message.aggregate([
            // Sort newest first so $first picks the latest activity
            { $sort: { timestamp: -1 } }, 
            
            // Group by the Customer's email
            {
                $group: {
                    _id: {
                        $cond: [{ $eq: ["$isAdmin", true] }, "$receiverEmail", "$senderEmail"]
                    },
                    lastMessage: { $first: "$text" },
                    lastMessageTime: { $first: "$timestamp" },
                    chatImage: { $first: "$packageImage" }, // Image sent in chat
                    unreadCount: {
                        $sum: { 
                            $cond: [
                                { $and: [{ $eq: ["$isAdmin", false] }, { $ne: ["$status", "read"] }] }, 
                                1, 0
                            ] 
                        }
                    }
                }
            },

            // LOOKUP 1: Get User Profile details
            {
                $lookup: {
                    from: "users",
                    localField: "_id",
                    foreignField: "email",
                    as: "userInfo"
                }
            },
            { $unwind: { path: "$userInfo", preserveNullAndEmptyArrays: true } },

            // LOOKUP 2: Get Order details (Matches using the User's Object ID found in userInfo)
            {
                $lookup: {
                    from: "orders",
                    localField: "userInfo._id", 
                    foreignField: "userId",
                    as: "orderInfo"
                }
            },

            // Add fields to simplify the final object
            {
                $addFields: {
                    latestOrder: { $arrayElemAt: ["$orderInfo", 0] } // Get most recent order
                }
            },

            // Final Projection for Flutter
            {
                $project: {
                    userEmail: "$_id",
                    userName: { $ifNull: ["$userInfo.fullName", "$_id"] },
                    profileImage: { $ifNull: ["$userInfo.profileImage", ""] },
                    lastMessage: 1,
                    lastMessageTime: 1,
                    unreadCount: 1,
                    // Use chat image if available, otherwise use package image from the order
                    packageImage: { $ifNull: ["$chatImage", "$latestOrder.packageImage"] },
                    packageName: "$latestOrder.packageDescription",
                    orderStatus: "$latestOrder.status"
                }
            },

            { $sort: { lastMessageTime: -1 } }
        ]);

        console.log(`[INBOX] Successfully retrieved ${chatThreads.length} threads.`);

        // 2. Generate Secure URLs for Images (Parallel processing)
        const signedThreads = await Promise.all(chatThreads.map(async (thread) => {
            try {
                if (thread.packageImage && !thread.packageImage.startsWith('http') && !thread.packageImage.startsWith('data:')) {
                    thread.packageImage = await getSecureUrl(thread.packageImage);
                }
                if (thread.profileImage && !thread.profileImage.startsWith('http') && !thread.profileImage.startsWith('data:')) {
                    thread.profileImage = await getSecureUrl(thread.profileImage);
                }
            } catch (signErr) {
                console.error(`Signing failed for ${thread.userEmail}:`, signErr.message);
            }
            return thread;
        }));

        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify(signedThreads) 
        };

    } catch (err) {
        console.error("Admin Inbox Aggregation Error:", err);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: "Failed to load customer chats." }) 
        };
    }
}

// --- UPDATED: GET ALL PENDING RIDER REQUESTS (Private IDrive e2 Signing) ---
if (path.includes('admin/rider-requests') && event.httpMethod === 'GET') {
    try {
        await connectDB();
        
        // 1. Fetch all pending orders
        const orders = await Order.find({ status: "Pending" })
            .sort({ createdAt: -1 })
            .lean();

        // 2. Process each order to attach user details and SIGN private images
        const ordersWithUserDetails = await Promise.all(orders.map(async (order) => {
            const user = await User.findById(order.userId)
                .select('profileImage email fullName')
                .lean();

            // SIGN the Package Image from E2
            let signedPackageImage = "";
            if (order.packageImage && !order.packageImage.startsWith('http')) {
                signedPackageImage = await getSecureUrl(order.packageImage);
            } else {
                signedPackageImage = order.packageImage; // Fallback for old base64/URLs
            }

            // SIGN the User Profile Image (if stored on E2)
            let signedProfileImage = "";
            if (user && user.profileImage && !user.profileImage.startsWith('http') && !user.profileImage.startsWith('data:')) {
                signedProfileImage = await getSecureUrl(user.profileImage);
            } else {
                signedProfileImage = user ? user.profileImage : "";
            }

            return {
                _id: order._id,
                userName: user ? user.fullName : (order.userName || "Customer"),
                userEmail: user ? user.email : order.senderEmail, 
                profileImage: signedProfileImage,
                packageImage: signedPackageImage, 
                pickupLocation: order.pickupLocation,
                deliveryLocation: order.deliveryLocation,
                weight: order.weight,
                packageDescription: order.packageDescription || "No description provided",
                status: order.status,
                orderMessage: `Package for ${order.receiverName} (${order.weight}kg)`,
                createdAt: order.createdAt
            };
        }));
        
        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify(ordersWithUserDetails) 
        };
    } catch (error) {
        console.error("Rider Requests Error:", error);
        return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
    }
}

// --- UPDATE ORDER STATUS ---
if (path.includes('update-order-status') && event.httpMethod === 'POST') {
    try {
        const { orderId, status } = JSON.parse(event.body);
        
        // Update the order in MongoDB
        const updatedOrder = await Order.findByIdAndUpdate(
            orderId, 
            { status: status }, 
            { new: true }
        );

        if (!updatedOrder) {
            return { statusCode: 404, headers, body: JSON.stringify({ error: "Order not found" }) };
        }

        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify({ message: `Order marked as ${status}`, order: updatedOrder }) 
        };
    } catch (error) {
        return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
    }
}

// --- ROUTE: GET USER ORDERS (For Client Dashboard) ---
if (path.includes('get-user-orders') && method === 'POST') {
    try {
        await connectDB();
        const { userId } = JSON.parse(event.body);

        if (!userId) {
            return { statusCode: 400, headers, body: JSON.stringify({ error: "User ID required" }) };
        }

        // 1. Find orders belonging to this user
        const orders = await Order.find({ userId }).sort({ createdAt: -1 }).lean();

        // 2. Process and Sign images so they are viewable
        const signedOrders = await Promise.all(orders.map(async (order) => {
            let signedPackageImage = "";
            
            // Check if it's a stored key (like "packages/123.jpg") and not a full URL
            if (order.packageImage && !order.packageImage.startsWith('http')) {
                signedPackageImage = await getSecureUrl(order.packageImage);
            } else {
                signedPackageImage = order.packageImage || "";
            }

            return {
                ...order,
                packageImage: signedPackageImage // Now a temporary viewable URL
            };
        }));

        return { 
            statusCode: 200, 
            headers, 
            body: JSON.stringify(signedOrders) 
        };
    } catch (error) {
        console.error("Fetch Orders Error:", error);
        return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
    }
}


   // --- FALLBACK: IF NO ROUTE MATCHES ---
        console.log(`[DEBUG] 404: No route matched for ${method} ${path}`);
        return { 
            statusCode: 404, 
            headers, 
            body: JSON.stringify({ error: "API endpoint not found." }) 
        };

    } catch (error) {
        console.error("Critical Error:", error);
        return { 
            statusCode: 500, 
            headers, 
            body: JSON.stringify({ error: "Internal Server Error", details: error.message }) 
        };
    }
};