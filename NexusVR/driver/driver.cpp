#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include "openvr_driver.h"
#include <chrono>
#include <cmath>
#include <cstring>
#include <sstream>
#include <algorithm>
using Clock=std::chrono::steady_clock;
struct Hand { int valid=0; double x=0,y=0,z=0,qx=0,qy=0,qz=0,qw=1; int pinch=0,grab=0,menu=0; };
static vr::HmdQuaternion_t quat(const vr::HmdMatrix34_t& m){
  vr::HmdQuaternion_t q{};
  q.w=std::sqrt(std::max(0.0,1.0+m.m[0][0]+m.m[1][1]+m.m[2][2]))/2;
  q.x=std::copysign(std::sqrt(std::max(0.0,1.0+m.m[0][0]-m.m[1][1]-m.m[2][2]))/2,m.m[2][1]-m.m[1][2]);
  q.y=std::copysign(std::sqrt(std::max(0.0,1.0-m.m[0][0]+m.m[1][1]-m.m[2][2]))/2,m.m[0][2]-m.m[2][0]);
  q.z=std::copysign(std::sqrt(std::max(0.0,1.0-m.m[0][0]-m.m[1][1]+m.m[2][2]))/2,m.m[1][0]-m.m[0][1]); return q;
}
static vr::HmdQuaternion_t mul(vr::HmdQuaternion_t a,vr::HmdQuaternion_t b){return {a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w};}
class Controller final: public vr::ITrackedDeviceServerDriver {
  bool left; vr::TrackedDeviceIndex_t idx=vr::k_unTrackedDeviceIndexInvalid; vr::DriverPose_t pose{};
  vr::VRInputComponentHandle_t trigger=0,click=0,grip=0,menu=0;
public:
  explicit Controller(bool l):left(l){pose.qWorldFromDriverRotation.w=pose.qDriverFromHeadRotation.w=pose.qRotation.w=1;}
  const char* serial() const {return left?"NEXUS-HAND-L":"NEXUS-HAND-R";}
  vr::EVRInitError Activate(vr::TrackedDeviceIndex_t i) override {
    idx=i; auto c=vr::VRProperties()->TrackedDeviceToPropertyContainer(i); auto p=vr::VRProperties();
    p->SetStringProperty(c,vr::Prop_TrackingSystemName_String,"nexushands"); p->SetStringProperty(c,vr::Prop_ManufacturerName_String,"Nexus Lab"); p->SetStringProperty(c,vr::Prop_ModelNumber_String,"Nexus Experimental Hand");
    p->SetStringProperty(c,vr::Prop_SerialNumber_String,serial()); p->SetStringProperty(c,vr::Prop_ControllerType_String,"nexushand"); p->SetStringProperty(c,vr::Prop_InputProfilePath_String,"{nexushands}/input/nexushand_profile.json");
    p->SetInt32Property(c,vr::Prop_ControllerRoleHint_Int32,left?vr::TrackedControllerRole_LeftHand:vr::TrackedControllerRole_RightHand);
    auto in=vr::VRDriverInput(); in->CreateScalarComponent(c,"/input/trigger/value",&trigger,vr::VRScalarType_Absolute,vr::VRScalarUnits_NormalizedOneSided); in->CreateBooleanComponent(c,"/input/trigger/click",&click); in->CreateBooleanComponent(c,"/input/grip/click",&grip); in->CreateBooleanComponent(c,"/input/application_menu/click",&menu); return vr::VRInitError_None;
  }
  void Deactivate() override{idx=vr::k_unTrackedDeviceIndexInvalid;}
  void EnterStandby() override{}
  void* GetComponent(const char*) override{return nullptr;}
  void DebugRequest(const char*,char* out,uint32_t n) override{if(n)out[0]=0;}
  vr::DriverPose_t GetPose() override{return pose;}
  void update(const Hand& h,bool fresh,const vr::TrackedDevicePose_t& head){
    if(idx==vr::k_unTrackedDeviceIndexInvalid)return;
    bool valid=fresh&&h.valid&&head.bPoseIsValid&&head.bDeviceIsConnected;
    pose.deviceIsConnected=fresh; pose.poseIsValid=valid; pose.result=valid?vr::TrackingResult_Running_OK:vr::TrackingResult_Running_OutOfRange;
    if(valid){auto& m=head.mDeviceToAbsoluteTracking; for(int r=0;r<3;r++)pose.vecPosition[r]=m.m[r][0]*h.x+m.m[r][1]*h.y+m.m[r][2]*h.z+m.m[r][3]; pose.qRotation=mul(quat(m),{h.qw,h.qx,h.qy,h.qz});}
    auto in=vr::VRDriverInput(); if(trigger)in->UpdateScalarComponent(trigger,valid&&h.pinch?1.f:0.f,0); if(click)in->UpdateBooleanComponent(click,valid&&h.pinch,0); if(grip)in->UpdateBooleanComponent(grip,valid&&h.grab,0); if(menu)in->UpdateBooleanComponent(menu,valid&&h.menu,0);
    vr::VRServerDriverHost()->TrackedDevicePoseUpdated(idx,pose,sizeof(pose));
  }
};
class Provider final:public vr::IServerTrackedDeviceProvider {
  Controller l{true},r{false}; SOCKET sock=INVALID_SOCKET; Hand a{},b{}; Clock::time_point last{}; bool wsa=false;
  static bool read(std::istringstream& s,Hand& h){ if(!(s>>h.valid>>h.x>>h.y>>h.z>>h.qx>>h.qy>>h.qz>>h.qw>>h.pinch>>h.grab>>h.menu))return false; return std::isfinite(h.x)&&std::isfinite(h.y)&&std::isfinite(h.z)&&std::isfinite(h.qx)&&std::isfinite(h.qy)&&std::isfinite(h.qz)&&std::isfinite(h.qw); }
public:
  vr::EVRInitError Init(vr::IVRDriverContext* c) override {
    VR_INIT_SERVER_DRIVER_CONTEXT(c); WSADATA w{}; if(WSAStartup(MAKEWORD(2,2),&w))return vr::VRInitError_Driver_Failed; wsa=true;
    sock=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP); sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_port=htons(9945);addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);u_long nb=1;
    if(sock==INVALID_SOCKET||bind(sock,reinterpret_cast<sockaddr*>(&addr),sizeof(addr))==SOCKET_ERROR||ioctlsocket(sock,FIONBIO,&nb)==SOCKET_ERROR){Cleanup();return vr::VRInitError_Driver_Failed;}
    vr::VRServerDriverHost()->TrackedDeviceAdded(l.serial(),vr::TrackedDeviceClass_Controller,&l);vr::VRServerDriverHost()->TrackedDeviceAdded(r.serial(),vr::TrackedDeviceClass_Controller,&r);return vr::VRInitError_None;
  }
  void Cleanup() override{if(sock!=INVALID_SOCKET){closesocket(sock);sock=INVALID_SOCKET;}if(wsa){WSACleanup();wsa=false;}VR_CLEANUP_SERVER_DRIVER_CONTEXT();}
  const char* const* GetInterfaceVersions() override{return vr::k_InterfaceVersions;}
  void RunFrame() override{
    if(sock==INVALID_SOCKET)return;char buf[2048]; for(int i=0;i<64;i++){int n=recv(sock,buf,sizeof(buf),0);if(n<=0)break;std::istringstream s(std::string(buf,n));std::string tag; Hand x{},y{}; if(s>>tag&&tag=="NVR1"&&read(s,x)&&read(s,y)){a=x;b=y;last=Clock::now();}}
    bool fresh=Clock::now()-last<std::chrono::milliseconds(450);vr::TrackedDevicePose_t head{};vr::VRServerDriverHost()->GetRawTrackedDevicePoses(0,&head,1);l.update(a,fresh,head);r.update(b,fresh,head);
  }
  bool ShouldBlockStandbyMode() override{return false;}void EnterStandby() override{} void LeaveStandby() override{}
};
static Provider provider;
extern "C" __declspec(dllexport) void* HmdDriverFactory(const char* name,int* code){if(!std::strcmp(name,vr::IServerTrackedDeviceProvider_Version))return &provider;if(code)*code=vr::VRInitError_Init_InterfaceNotFound;return nullptr;}
