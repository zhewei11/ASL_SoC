cmake_minimum_required(VERSION 3.16)
project(asl_motion C)

add_library(asl_motion STATIC
    src/asl_motion.c
    generated/asl_actions_generated.c
)
target_include_directories(asl_motion PUBLIC
    include
    generated
)
target_compile_features(asl_motion PUBLIC c_std_11)

add_library(asl_soc_hx5_port STATIC
    ports/asl_soc_hx5_port.c
)
target_include_directories(asl_soc_hx5_port PUBLIC
    include
    ports
    ../fw/include
)
target_link_libraries(asl_soc_hx5_port PUBLIC asl_motion)
target_compile_features(asl_soc_hx5_port PUBLIC c_std_11)

add_library(asl_soc_cnn_port STATIC
    ports/asl_soc_cnn_port.c
)
target_include_directories(asl_soc_cnn_port PUBLIC
    include
    ports
    ../fw/include
)
target_link_libraries(asl_soc_cnn_port PUBLIC asl_motion)
target_compile_features(asl_soc_cnn_port PUBLIC c_std_11)
