#version 150

#moj_import <light.glsl>
const vec3 LIGHT0_DIRECTION = vec3(0.2, 1.0, -0.7); // Default light 0 direction everywhere except in inventory
const vec3 LIGHT1_DIRECTION = vec3(-0.2, 1.0, 0.7); // Default light 1 direction everywhere except in nether and inventory

mat3 getWorldMat(vec3 light0, vec3 light1) {
    mat3 V = mat3(LIGHT0_DIRECTION, LIGHT1_DIRECTION, cross(LIGHT0_DIRECTION, LIGHT1_DIRECTION));
    mat3 W = mat3(light0, light1, cross(light0, light1));
    return W * inverse(V);
}

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV1;
in ivec2 UV2;
in vec3 Normal;

uniform sampler2D Sampler0;
uniform sampler2D Sampler1;
uniform sampler2D Sampler2;

uniform mat4 ModelViewMat;
uniform mat4 ProjMat;

uniform vec3 Light0_Direction;
uniform vec3 Light1_Direction;
uniform vec3 ChunkOffset;

out float vertexDistance;
out vec4 vertexColor;
out vec4 lightMapColor;
out vec4 overlayColor;
out vec2 texCoord0;
out vec4 normal;

out vec4 wx_passColor;  //for debugging
out vec3 wx_passMPos;   //for experimental normal calculation
out vec3 wx_passNormal; //for debugging
out vec2 wx_scalingOrigin; //axis not scaled around MUST be 0
out vec2 wx_scaling;
out vec2 wx_maxUV;
out vec2 wx_minUV;
out vec2 wx_UVDisplacement;
out float wx_isEdited;

#define AS_ROTATED 32   // how long to stretch along normal to simulate 90 deg face
#define AS_8XALIGNED 8

#define TRANSFORM_NONE (0<<4)
#define TRANSFORM_OUTER (1<<4)
#define TRANSFORM_OUTER_REVERSED (2<<4)
#define TRANSFORM_INNER_REVERSED (3<<4)
#define SCALEDIR_X_PLUS (0<<6)
#define SCALEDIR_X_MINUS (1<<6)
#define SCALEDIR_Y_PLUS (2<<6)
#define SCALEDIR_Y_MINUS (3<<6)
#define F_ENABLED (0x80)

void writeDefaults(int faceId);
void fixScaling(int faceId);

void main() {
    vertexDistance = length((ModelViewMat * vec4(Position, 1.0)).xyz);
    vertexColor = minecraft_mix_light(Light0_Direction, Light1_Direction, Normal, Color);
    lightMapColor = texelFetch(Sampler2, UV2 / 16, 0);
    overlayColor = texelFetch(Sampler1, UV1, 0);
    texCoord0 = UV0;
    normal = ProjMat * ModelViewMat * vec4(Normal, 0.0);

    

    if(gl_VertexID >= 18*8){ //is second layer
        vec4 topRightPixel = texelFetch(Sampler0, ivec2(0, 0), 0); //Macs can't texelfetch in vertex shader?

        if(0==0/*topRightPixel.r == 1.0 && topRightPixel.a == 1.0*/){ 
            int cornerId = gl_VertexID % 4;

            vec3 newPos = Position;
            int faceId = gl_VertexID / 4;
            vec4 pxData = texelFetch(Sampler0, ivec2((faceId-8)%8, (faceId-8)/8), 0)*256;
            int data0 = int(pxData.r+0.5);
            int data1 = int(pxData.g+0.5);
            int data2 = int(pxData.b+0.5); 

            //<debug>
            switch(faceId) { 
            case 39: // Bottom hat 
                data0 = F_ENABLED | 0x0C | TRANSFORM_INNER_REVERSED;
                data1 = 0x8 | SCALEDIR_Y_MINUS;
                data2 = 0;
                break;
            case 67: data0 = (1<<0) | (1<<3) | TRANSFORM_OUTER; data1 = SCALEDIR_X_PLUS; break;  //Right jacket
            case 66: data0 = (1<<1) | (1<<2) | TRANSFORM_OUTER; data1 = SCALEDIR_X_MINUS; break;  //Left jacket
            case 69: data0 = (1<<0) | (1<<1) | TRANSFORM_OUTER; data1 = SCALEDIR_Y_PLUS; break;  //Bottom jacket
            case 71: data0 = (1<<2) | (1<<3) | TRANSFORM_OUTER; data1 = SCALEDIR_Y_PLUS; break;  //Back jacket
            } 
            data0 = data0 | F_ENABLED; //enabled all faces for debug testing
            //</debug>

            if(data0 & F_ENABLED){
                writeDefaults(faceId);
                
                int cornerBits = data0 & 0xf;
                int transformType = data0 & 0x70;
                int uvX = data1 & 0x3F;
                int uvY = data2 & 0x3F;
                int strechDirection = data1 & 0xC0;

                switch(strechDirection){
                    case SCALEDIR_X_PLUS: 
                        wx_scalingOrigin = vec2(wx_minUV.x, (wx_maxUV.y+wx_minUV.y)/2);
                        break;
                    case SCALEDIR_X_MINUS: 
                        wx_scalingOrigin = vec2(wx_maxUV.x, (wx_maxUV.y+wx_minUV.y)/2);
                        break;
                    case SCALEDIR_Y_PLUS: 
                        wx_scalingOrigin = vec2((wx_maxUV.x+wx_minUV.x)/2, wx_minUV.y);
                        break;
                    case SCALEDIR_Y_MINUS: 
                        wx_scalingOrigin = vec2((wx_maxUV.x+wx_minUV.x)/2, wx_maxUV.y);
                        break;
                }

                int isSelectedCorner = (1<<cornerId) & cornerBits;
                //vec2 size = wx_maxUV-wx_minUV; //Could be used to generalize wx_scaling i think

                if(float(uvX)/64.0 + wx_maxUV.x > 1) uvX -= 64; // Seeings as UV frag cut is capped inside 0..1 must 
                if(float(uvY)/64.0 + wx_maxUV.y > 1) uvY -= 64; //  this makes sure offset wraps correctly
                wx_UVDisplacement = vec2(uvX,uvY) / 64.0;

                switch (faceId){
                case 39: // Bottom hat 
                    wx_isEdited = 1;
                    switch(transformType){
                    case TRANSFORM_OUTER:
                        if(isSelectedCorner) newPos += Normal*AS_ROTATED;
                        wx_scaling = vec2(1, AS_ROTATED*2/1.1);
                        break;
                    case TRANSFORM_OUTER_REVERSED:
                        newPos -= Normal/16.0*8.43;
                        if(isSelectedCorner) newPos += Normal*-AS_ROTATED;
                        wx_scaling = vec2(1, AS_ROTATED*2/1.1);
                        break;
                    case TRANSFORM_INNER_REVERSED:
                        wx_minUV -= vec2(0,8)/64; //needed since reverse. Effectively shifts the clipmask
                        wx_maxUV -= vec2(0,8)/64;
                        wx_UVDisplacement += vec2(0,8)/64.0; //needed since reverse. Effectively shifts the clipmask
                        if(isSelectedCorner) newPos += Normal*-AS_8XALIGNED;
                        wx_scaling = vec2(1.12, AS_8XALIGNED*2*1.01);
                        overlayColor = vec4(1,0,0,1);
                        break;
                    }
                    break;

                case 67: //Right Shirt
                    wx_isEdited = 1;
                    switch(transformType) {
                    case TRANSFORM_OUTER:
                        if(isSelectedCorner) newPos += Normal*AS_ROTATED;
                        wx_scaling = vec2(AS_ROTATED*4, 1);
                        break;
                    }
                    break;
                    
                case 66: //Left Shirt
                    wx_isEdited = 1;
                    switch(transformType) {
                    case TRANSFORM_OUTER:
                        if(isSelectedCorner) newPos += Normal*AS_ROTATED;
                        wx_scaling = vec2(AS_ROTATED*4, 1);
                        break;
                    }
                    break;
                
                case 69: // Bottom Shirt
                    wx_isEdited = 1;
                    switch(transformType) {
                    case TRANSFORM_OUTER:
                        if(isSelectedCorner) newPos += Normal*AS_ROTATED;
                        wx_scaling = vec2(1, AS_ROTATED*4);
                        break;
                    }
                    break;

                case 71: // Back jacket
                    wx_isEdited = 1;
                    switch(transformType) {
                    case TRANSFORM_OUTER:
                        if(isSelectedCorner) newPos += Normal*AS_ROTATED;
                        wx_scaling = vec2(1, AS_ROTATED*4/3);
                        break;
                    }
                    break;
                }
                if(wx_isEdited){
                    wx_passColor = Color;
                    wx_passMPos = -(ModelViewMat * vec4(newPos, 1.0)).xyz;
                    gl_Position = ProjMat * ModelViewMat * vec4(newPos, 1.0);
                } else {
                    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
                }    
            } else {
                gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
            }
        } else {
            gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
        }        
    } else {
        gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
        
        //passNormal = Normal;
        //passColor = Color;
    }

}

void writeDefaults(int faceId){
    switch(faceId){
    case 39: //Bottom Hat
        wx_minUV = vec2(48, 0)/64.0;
        wx_maxUV = vec2(56, 8)/64.0;
        break;
    case 67: //Right Shirt
        wx_minUV = vec2(16, 36)/64.0;
        wx_maxUV = vec2(20, 48)/64.0;
        break;
    case 66: //Left Shirt
        wx_minUV = vec2(28, 36)/64.0;
        wx_maxUV = vec2(32, 48)/64.0;
        break;
    case 69: //Bottom Shirt
        wx_minUV = vec2(28, 32)/64.0;
        wx_maxUV = vec2(36, 36)/64.0;
        break;
    case 71: //Back Shirt
        wx_minUV = vec2(32, 36)/64.0;
        wx_maxUV = vec2(40, 48)/64.0;
    }
}

    /*
    if(gl_VertexID >= 5*8+4 && gl_VertexID <= 5*8+7){ //back body

        mat3 fromWorld = getWorldMat(Light0_Direction,Light1_Direction);
        mat3 toWorld = inverse(fromWorld);
        vec3 wPos = toWorld*Position;
        vec3 wNorm = toWorld*Normal;

        //float anim = abs(fract(GameTime*600)-0.5)-0.25;

        vec3 wDown = vec3(0,-1,0);
        vec3 wSide = cross(wDown, wNorm);

        if(gl_VertexID == 5*8+4){
            wPos += -wSide/16.0*3;
        } else if(gl_VertexID == 5*8+5){
            wPos += wSide/16.0*3;
        } else if(gl_VertexID == 5*8+6){
            wPos += wSide/16.0*3;
            wPos += wNorm/16*6;
        } else if(gl_VertexID == 5*8+7){
            wPos += -wSide/16.0*3;
            wPos += wNorm/16*6;
        }

        gl_Position = ProjMat * ModelViewMat * vec4(fromWorld*wPos, 1.0);

        overlayColor = vec4(abs(wPos)/4.0,0);
    }*/
    /*
    isEdited = 0;
    if(gl_VertexID >= (18+1)*8+4 && gl_VertexID <= (18+1)*8+7){ //bottom head

        vec3 newPos = Position;
        if(mod(gl_VertexID,8) == 6 || mod(gl_VertexID,8) == 7){ //back side
            newPos += Normal*-AS_ROTATED;
        } else { //front side
            newPos -= Normal/16.0*8.45;
        }
        gl_Position = ProjMat * ModelViewMat * vec4(newPos, 1.0);

        passColor = Color;
        passMPos = -(ModelViewMat * vec4(newPos, 1.0)).xyz;
        passInvTrans = mat3(inverse(ProjMat * ModelViewMat));
        isEdited = 1.0;
    }
    */
    //
    /*
    T/B Hat     -> (Front,Back) x (Ears,Beard)
    L/R Hat     -> (Front,Back) x (Side Ears)
    L/R Jacket  -> (Front,Back) x (Wings)
    T/B Jacket  -> (Front,Back,Left,Right) x (Collar,Coat)


    /*
    mat3 fromWorld = getWorldMat(Light0_Direction,Light1_Direction);
    mat3 toWorld = inverse(fromWorld);
    vec3 wPos = toWorld*Position;

    overlayColor = vec4(abs(wPos)/4.0,0);



    /*
    if(gl_VertexID == 14*8+1){  
        overlayColor = vec4(0,1,0,0);
        
        mat3 fromWorld = getWorldMat(Light0_Direction,Light1_Direction);
        mat3 toWorld = inverse(fromWorld);
        vec3 wPos = toWorld*Position;

        vec3 wNorm = toWorld*Normal; //orthogonal to face
        vec3 wPer = wNorm.xzy;

        wPos += wNorm/16;

        vec3 newPos = fromWorld*wPos;

        gl_Position = ProjMat * ModelViewMat * vec4(newPos, 1.0); 
    }
    /*
    
    else if(texCoord0.x == 4.0/64.0){
        overlayColor = vec4(1,1,0,0);

        mat3 fromWorld = getWorldMat(Light0_Direction,Light1_Direction);
        mat3 toWorld = inverse(fromWorld);
        vec3 wPos = toWorld*Position;

        vec3 wNorm = toWorld*Normal; //orthogonal to face
        vec3 wPer = wNorm.xzy;

        wPos += wNorm/16;

        vec3 newPos = fromWorld*wPos;

        gl_Position = ProjMat * ModelViewMat * vec4(newPos, 1.0); 
        
    }
    else if(texCoord0.x == 8.0/64.0){
        overlayColor = vec4(0,1,0,0);
    }*/

    //texCoord0.x += 2;
    //texCoord0.y += 10;

    //overlayColor.r = UV0.x;
    //overlayColor.g = UV0.y;
    //overlayColor.a = 0;